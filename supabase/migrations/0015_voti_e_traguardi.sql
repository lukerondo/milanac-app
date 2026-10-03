-- Voti dopo la partita (segreti), Uomo partita, Squadra della settimana e statistiche
-- per i traguardi. Le medie si leggono solo dalle funzioni: nessuno vede chi ha votato cosa.

create table if not exists public.match_ratings (
  match_id uuid not null references public.matches on delete cascade,
  voter_id uuid not null default auth.uid() references public.profiles on delete cascade,
  player_id uuid not null references public.profiles on delete cascade,
  rating smallint not null check (rating between 1 and 10),
  created_at timestamptz not null default now(),
  primary key (match_id, voter_id, player_id),
  check (voter_id <> player_id)
);
create index if not exists match_ratings_player_idx on public.match_ratings (player_id);

alter table public.match_ratings enable row level security;
drop policy if exists "propri voti" on public.match_ratings;
create policy "propri voti" on public.match_ratings for all
  using (voter_id = auth.uid())
  with check (
    voter_id = auth.uid() and is_member()
    -- si vota solo a partita finita (risultato inserito)
    and exists (select 1 from matches m where m.id = match_id
                and m.goals_for is not null and m.goals_against is not null)
    -- e solo membri approvati
    and exists (select 1 from profiles p where p.id = player_id
                and p.active and p.club_role <> 'pending')
  );

-- Media e voti per ogni giocatore della partita; l'Uomo partita è il primo con almeno 2 voti.
create or replace function public.match_rating_summary(p_match uuid)
returns table (player_id uuid, avg_rating numeric, votes int, is_mvp boolean)
language sql stable security definer set search_path = public as $$
  with s as (
    select r.player_id, round(avg(r.rating)::numeric, 1) as avg_rating, count(*)::int as votes
    from match_ratings r
    where r.match_id = p_match and is_member()
    group by r.player_id
  ), ranked as (
    select s.*, row_number() over (
      order by (s.votes >= 2) desc, s.avg_rating desc, s.votes desc) as rn
    from s
  )
  select player_id, avg_rating, votes, (rn = 1 and votes >= 2) as is_mvp
  from ranked order by rn
$$;

-- L'Uomo partita di ogni partita votata (almeno 2 voti).
create or replace function public.match_mvps()
returns table (match_id uuid, player_id uuid, avg_rating numeric, votes int,
               played_at timestamptz, team text)
language sql stable security definer set search_path = public as $$
  select distinct on (r.match_id)
         r.match_id, r.player_id, round(avg(r.rating)::numeric, 1), count(*)::int,
         m.played_at, m.team
  from match_ratings r join matches m on m.id = r.match_id
  where is_member()
  group by r.match_id, r.player_id, m.played_at, m.team
  having count(*) >= 2
  order by r.match_id, avg(r.rating) desc, count(*) desc
$$;

-- Squadra della settimana (lunedì-domenica) di una squadra: i migliori 11 per media voti.
create or replace function public.team_of_the_week(p_week date, p_team text)
returns table (player_id uuid, avg_rating numeric, votes int, matches int)
language sql stable security definer set search_path = public as $$
  select r.player_id, round(avg(r.rating)::numeric, 1), count(*)::int,
         count(distinct r.match_id)::int
  from match_ratings r join matches m on m.id = r.match_id
  where is_member() and m.team = p_team
    and (m.played_at at time zone 'Europe/Rome')::date >= date_trunc('week', p_week)::date
    and (m.played_at at time zone 'Europe/Rome')::date < date_trunc('week', p_week)::date + 7
  group by r.player_id
  having count(*) >= 2
  order by avg(r.rating) desc, count(*) desc
  limit 11
$$;

-- Numeri per i traguardi di un giocatore (tutta la storia, non solo gli ultimi 60 giorni).
create or replace function public.player_stats(p_player uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with att as (
    select status, date from attendance where player_id = p_player
  ), months as (
    select date_trunc('month', date) as m,
           count(*) filter (where status = 'presente') as pres,
           count(*) filter (where status = 'ritardo') as late
    from att group by 1
  ), weekly as (
    select date_trunc('week', m.played_at at time zone 'Europe/Rome')::date as wk, m.team,
           r.player_id, avg(r.rating) as a, count(*) as c
    from match_ratings r join matches m on m.id = r.match_id
    group by 1, 2, 3 having count(*) >= 2
  ), ranked as (
    select *, row_number() over (partition by wk, team order by a desc, c desc) as rn from weekly
  )
  select case when not is_member() then null else jsonb_build_object(
    'presences', (select count(*) from att where status in ('presente', 'ritardo')),
    'late', (select count(*) from att where status = 'ritardo'),
    'clean_month', exists (select 1 from months where pres >= 8 and late = 0),
    'mvp', (select count(*) from match_mvps() v where v.player_id = p_player),
    'totw', (select count(*) from ranked where player_id = p_player and rn <= 11)
  ) end
$$;

revoke all on function public.match_rating_summary(uuid) from public, anon;
revoke all on function public.match_mvps() from public, anon;
revoke all on function public.team_of_the_week(date, text) from public, anon;
revoke all on function public.player_stats(uuid) from public, anon;
grant execute on function public.match_rating_summary(uuid) to authenticated;
grant execute on function public.match_mvps() to authenticated;
grant execute on function public.team_of_the_week(date, text) to authenticated;
grant execute on function public.player_stats(uuid) to authenticated;

-- Risultato inserito → notifica "vota i compagni" ai giocatori della squadra.
create or replace function public.on_match_result() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.goals_for is not null and new.goals_against is not null
     and (tg_op = 'INSERT' or old.goals_for is null or old.goals_against is null) then
    perform notify_push(jsonb_build_object('kind', 'match_result', 'id', new.id));
  end if;
  return new;
end $$;
drop trigger if exists match_result on public.matches;
create trigger match_result after insert or update of goals_for, goals_against on public.matches
  for each row execute function public.on_match_result();
