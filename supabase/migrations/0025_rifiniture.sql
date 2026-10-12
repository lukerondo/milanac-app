-- Rifiniture dalla review finale (ottobre 2026).
--  1) Eliminare una partita toglie le sue carte speciali e il loro annuncio, e ricontrolla la
--     serie del portiere delle due partite ufficiali successive.
--  2) La blu elettrico ha sempre la precedenza: chi la riceve perde la nero/oro della stessa partita.
--  3) Carte nero/oro: correggere un bonus non riavvisa tutta la squadra; chi cambia reparto
--     tiene la sua carta (stesse date, nessun nuovo avviso).
--  4) Formazione: l'ora di pubblicazione è quella del server; il portiere del risultato viene dalla
--     formazione pubblicata (non dalla bozza) e si ricalcola scegliendo "dalla formazione"; un
--     giocatore uscito dal club non compare tra i titolari dell'annuncio.
--  5) Classifica dei tornei e contatti social si salvano in una sola transazione.
--  6) Nome, cognome e nascita li vedono solo l'interessato e il Direttivo (tabella a parte:
--     prima erano colonne di profiles, leggibili da ogni membro).
--  7) Nuovo ingresso nel club: avviso nella Sala Direttivo (e notifica al Direttivo).
--  8) Tempo reale anche per classifica dei tornei, notizie, contatti del club, versioni del
--     regolamento e dati anagrafici.

-- ---------------------------------------------------------------- 1) partita eliminata
alter table public.special_cards drop constraint if exists special_cards_match_id_fkey;
alter table public.special_cards add constraint special_cards_match_id_fkey
  foreign key (match_id) references public.matches(id) on delete cascade;

create or replace function public.on_match_deleted() returns trigger
language plpgsql security definer set search_path = public as $$
declare nxt uuid;
begin
  delete from messages
  where kind = 'system' and meta->>'type' = 'special_cards' and meta->>'match' = old.id::text;
  if old.kind = 'torneo' then
    for nxt in select x.id from matches x
               where x.team = old.team and x.kind = 'torneo'
                 and x.goals_for is not null and x.goals_against is not null
                 and (x.played_at, x.created_at, x.id) > (old.played_at, old.created_at, old.id)
               order by x.played_at, x.created_at, x.id
               limit 2 loop
      perform award_blue_cards(nxt, false);
    end loop;
  end if;
  return old;
end $$;
drop trigger if exists match_deleted on public.matches;
create trigger match_deleted after delete on public.matches
  for each row execute function public.on_match_deleted();

-- ---------------------------------------------------------------- 2) precedenza della blu
create or replace function public.award_blue_cards(p_match uuid, p_cascade boolean default true)
returns int
language plpgsql security definer set search_path = public as $$
declare
  m matches%rowtype;
  r record;
  n int := 0;
  hat_tricks uuid[] := '{}';
  keeper_streak boolean := false;
  removed int;
  replaced int;
  nxt uuid;
begin
  select * into m from matches where id = p_match;
  if m.id is null then return 0; end if;
  if m.goals_for is not null and m.goals_against is not null then
    select coalesce(array_agg(s.player_id), '{}') into hat_tricks
    from scorer_goals(m.scorers, m.team) s where s.goals >= 3;
    keeper_streak := m.kind = 'torneo' and m.goals_against = 0 and m.goalkeeper_id is not null
      and (select count(*) from (
             select x.goals_against, x.goalkeeper_id from matches x
             where x.team = m.team and x.kind = 'torneo' and x.id <> m.id
               and x.goals_for is not null and x.goals_against is not null
               and (x.played_at, x.created_at, x.id) < (m.played_at, m.created_at, m.id)
             order by x.played_at desc, x.created_at desc, x.id desc
             limit 2) prev
           where prev.goals_against = 0 and prev.goalkeeper_id = m.goalkeeper_id) = 2;
  end if;
  delete from special_cards
  where match_id = m.id and kind = 'blu'
    and ((reason like 'Tripletta contro %' and not (player_id = any(hat_tricks)))
      or (reason = 'Tre partite di fila senza subire gol'
          and not (keeper_streak and player_id = m.goalkeeper_id)));
  get diagnostics removed = row_count;
  for r in select s.player_id, p.field_position
           from scorer_goals(m.scorers, m.team) s join profiles p on p.id = s.player_id
           where s.player_id = any(hat_tricks) loop
    if give_special_card(r.player_id, 'blu', coalesce(reparto_of(r.field_position), 'ATT'), 5,
                         'Tripletta contro ' || m.opponent, m.id, m.team) is not null then
      n := n + 1;
    end if;
  end loop;
  if keeper_streak then
    if give_special_card(m.goalkeeper_id, 'blu', 'POR', 5,
                         'Tre partite di fila senza subire gol', m.id, m.team) is not null then
      n := n + 1;
    end if;
  end if;
  -- La blu ha la precedenza: la nero/oro della stessa partita, se c'era, si toglie.
  delete from special_cards s
  where s.match_id = m.id and s.kind = 'nero_oro'
    and exists (select 1 from special_cards b
                where b.match_id = m.id and b.kind = 'blu' and b.player_id = s.player_id);
  get diagnostics replaced = row_count;
  -- L'annuncio in Comunicazioni, se c'è, segue le carte.
  if (removed > 0 or n > 0 or replaced > 0) and exists (
       select 1 from messages
       where kind = 'system' and meta->>'type' = 'special_cards' and meta->>'match' = m.id::text) then
    perform announce_special_cards(m.id);
  end if;
  if p_cascade and m.kind = 'torneo' then
    for nxt in select x.id from matches x
               where x.team = m.team and x.kind = 'torneo' and x.id <> m.id
                 and x.goals_for is not null and x.goals_against is not null
                 and (x.played_at, x.created_at, x.id) > (m.played_at, m.created_at, m.id)
               order by x.played_at, x.created_at, x.id
               limit 2 loop
      perform award_blue_cards(nxt, false);
    end loop;
  end if;
  return n;
end $$;
revoke all on function public.award_blue_cards(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3) carte nero/oro
create or replace function public.assign_special_cards(p_match uuid, p_awards jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  m matches%rowtype;
  a jsonb;
  pid uuid;
  b int;
  rep text;
  pos text;
  reps text[] := '{}';
  kept uuid[] := '{}';
  cid uuid;
  n int := 0;
  moved jsonb;
  prev jsonb;
begin
  if not is_direttivo() then raise exception 'Solo il Direttivo assegna le carte speciali'; end if;
  select * into m from matches where id = p_match;
  if m.id is null then raise exception 'Partita non trovata'; end if;
  if m.goals_for is null or m.goals_against is null then
    raise exception 'Inserisci prima il risultato della partita';
  end if;
  if p_awards is null or jsonb_typeof(p_awards) <> 'array' then
    raise exception 'Elenco dei premiati non valido';
  end if;
  for a in select * from jsonb_array_elements(p_awards) loop
    pid := (a->>'player_id')::uuid;
    b := coalesce((a->>'bonus')::int, 5);
    if b not between 1 and 5 then raise exception 'Il bonus va da +1 a +5'; end if;
    select field_position into pos from profiles p
    where p.id = pid and p.active and p.club_role <> 'pending' and m.team = any(p.teams);
    if not found then raise exception 'Il giocatore non è della squadra'; end if;
    if pid = any(kept) then raise exception 'Un giocatore riceve una sola carta nero/oro'; end if;
    rep := coalesce(nullif(upper(a->>'reparto'), ''), reparto_of(pos));
    if rep is null or rep not in ('POR', 'DIF', 'CEN', 'ATT') then
      raise exception 'Reparto sconosciuto: imposta la posizione in campo del giocatore';
    end if;
    if rep = any(reps) then raise exception 'Una sola carta nero/oro per reparto (%)', rep; end if;
    reps := reps || rep;
    kept := kept || pid;
  end loop;
  -- Si tolgono le carte che cambiano (giocatore non più in elenco o reparto diverso); chi
  -- resta premiato ma cambia reparto ritrova la sua carta con le stesse date, senza avvisi.
  with gone as (
    delete from special_cards s
    where s.match_id = m.id and s.kind = 'nero_oro'
      and not exists (select 1 from unnest(kept, reps) as k(pid, rep)
                      where k.pid = s.player_id and k.rep = s.reparto)
    returning s.player_id, s.starts_at, s.ends_at, s.assigned_by
  )
  select coalesce(jsonb_object_agg(player_id, jsonb_build_object(
           'starts_at', starts_at, 'ends_at', ends_at)), '{}'::jsonb)
    into moved
  from gone where player_id = any(kept);
  for a in select * from jsonb_array_elements(p_awards) loop
    pid := (a->>'player_id')::uuid;
    b := coalesce((a->>'bonus')::int, 5);
    rep := reps[array_position(kept, pid)];
    if exists (select 1 from special_cards where match_id = m.id and player_id = pid and kind = 'blu') then
      continue;  -- la blu elettrico ha la precedenza
    end if;
    select id into cid from special_cards
    where match_id = m.id and player_id = pid and kind = 'nero_oro';
    prev := moved->(pid::text);
    if cid is not null then
      update special_cards set bonus = b, assigned_by = auth.uid() where id = cid;
    elsif prev is not null then
      insert into special_cards (player_id, kind, reparto, bonus, reason, match_id, team,
                                 assigned_by, starts_at, ends_at)
      values (pid, 'nero_oro', rep, b, 'Carta della settimana', m.id, m.team, auth.uid(),
              (prev->>'starts_at')::timestamptz, (prev->>'ends_at')::timestamptz);
    else
      perform give_special_card(pid, 'nero_oro', rep, b, 'Carta della settimana', m.id, m.team);
      n := n + 1;
    end if;
  end loop;
  perform announce_special_cards(m.id);
  -- L'avviso alla squadra solo quando arrivano carte nuove (non per un bonus corretto).
  if n > 0 then
    perform notify_push(jsonb_build_object('kind', 'special_cards_week', 'match', m.id));
  end if;
  return n;
end $$;
revoke all on function public.assign_special_cards(uuid, jsonb) from public, anon;
grant execute on function public.assign_special_cards(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------- 4) formazione
-- Ora di pubblicazione dal server (il telefono del Direttivo può essere avanti o indietro).
create or replace function public.formations_server_time() returns trigger
language plpgsql as $$
begin
  if new.published_at is not null and new.published_at is distinct from old.published_at then
    new.published_at := now();
  end if;
  return new;
end $$;
drop trigger if exists formations_server_time on public.formations;
create trigger formations_server_time before update of published_at on public.formations
  for each row execute function public.formations_server_time();

-- Il portiere dell'ultima formazione PUBBLICATA (il posto 0 è il portiere in ogni modulo);
-- per le formazioni pubblicate prima dei giocatori "congelati" vale ancora il posto POR.
create or replace function public.formation_goalkeeper(p_team text) returns uuid
language sql stable security definer set search_path = public as $$
  select case when f.published_players is not null
              then nullif(f.published_players->>'0', '')::uuid
              else (select s.player_id from formation_slots s
                    where s.formation_id = f.id and s.label = 'POR' limit 1) end
  from formations f
  where f.team = p_team and f.published_at is not null
  order by f.published_at desc
  limit 1
$$;
revoke all on function public.formation_goalkeeper(text) from public, anon, authenticated;

-- Il portiere si ricava dalla formazione al primo risultato e ogni volta che si sceglie di
-- nuovo "dalla formazione" (portiere vuoto con il risultato già inserito).
create or replace function public.matches_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.goalkeeper_id is null and new.goals_for is not null and new.goals_against is not null
     and (tg_op = 'INSERT' or old.goals_for is null or old.goals_against is null
          or old.goalkeeper_id is not null) then
    new.goalkeeper_id := formation_goalkeeper(new.team);
  end if;
  return new;
end $$;

-- Annuncio della formazione: chi è uscito dal club non compare tra i titolari.
create or replace function public.on_formation_published() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ch uuid := (select id from channels where slug = 'comunicazioni');
  squadra text := case new.team when 'futuro' then 'Milan AC Futuro' else 'Milan AC' end;
  titolari text;
  panchina text;
begin
  if new.published_at is null or new.published_at is not distinct from old.published_at then
    return new;
  end if;
  perform notify_push(jsonb_build_object('kind', 'formation', 'id', new.id));
  if ch is null then return new; end if;
  select string_agg(s.label || ' ' || p.display_name, ', ' order by s.slot_index)
    into titolari
  from formation_slots s join profiles p on p.id = s.player_id
  where s.formation_id = new.id and p.active and p.club_role <> 'pending';
  select string_agg(p.display_name, ', ' order by p.display_name) into panchina
  from profiles p
  where p.active and p.club_role <> 'pending' and new.team = any(p.teams)
    and not exists (select 1 from formation_slots s
                    where s.formation_id = new.id and s.player_id = p.id);
  insert into messages (channel_id, author_id, kind, body, meta)
  values (ch, new.published_by, 'system',
          'Formazione ' || squadra || ' (' || coalesce(new.published_module, new.module) || '): '
          || coalesce(titolari, 'da definire')
          || case when panchina is null then '' else '. Panchina: ' || panchina end,
          jsonb_build_object('type', 'formation', 'team', new.team, 'id', new.id));
  return new;
end $$;

-- ---------------------------------------------------------------- 5) salvataggi in un colpo solo
-- Classifica di un torneo: [{"team_name", "won", "drawn", "lost", "goals_for",
-- "goals_against", "is_us"}], sostituisce quella di prima.
create or replace function public.save_standings(p_tournament uuid, p_rows jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_direttivo() then raise exception 'Solo il Direttivo modifica la classifica'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 40 then
    raise exception 'Classifica non valida';
  end if;
  if not exists (select 1 from tournaments where id = p_tournament) then
    raise exception 'Torneo non trovato';
  end if;
  delete from tournament_standings where tournament_id = p_tournament;
  insert into tournament_standings (tournament_id, team_name, won, drawn, lost,
                                    goals_for, goals_against, is_us)
  select p_tournament, btrim(r->>'team_name'),
         coalesce((r->>'won')::smallint, 0), coalesce((r->>'drawn')::smallint, 0),
         coalesce((r->>'lost')::smallint, 0), coalesce((r->>'goals_for')::smallint, 0),
         coalesce((r->>'goals_against')::smallint, 0), coalesce((r->>'is_us')::boolean, false)
  from jsonb_array_elements(p_rows) r;
end $$;
revoke all on function public.save_standings(uuid, jsonb) from public, anon;
grant execute on function public.save_standings(uuid, jsonb) to authenticated;

-- Contatti social del club: [{"kind", "url"}] nell'ordine, sostituiscono quelli di prima.
create or replace function public.save_club_links(p_links jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_direttivo() then raise exception 'Solo il Direttivo modifica i contatti'; end if;
  if p_links is null or jsonb_typeof(p_links) <> 'array' or jsonb_array_length(p_links) > 20 then
    raise exception 'Contatti non validi';
  end if;
  if exists (select 1 from jsonb_array_elements(p_links) l
             where coalesce(l->>'url', '') !~* '^https?://' or char_length(l->>'url') > 300
                or coalesce(l->>'kind', '') = '') then
    raise exception 'Link non valido: deve iniziare con https://';
  end if;
  delete from club_links where true;
  insert into club_links (kind, url, sort_order)
  select l->>'kind', btrim(l->>'url'), (i - 1)::smallint
  from jsonb_array_elements(p_links) with ordinality as t(l, i);
end $$;
revoke all on function public.save_club_links(jsonb) from public, anon;
grant execute on function public.save_club_links(jsonb) to authenticated;

-- ---------------------------------------------------------------- 6) dati anagrafici riservati
create table if not exists public.profile_private (
  id uuid primary key references public.profiles on delete cascade,
  first_name text check (first_name is null or char_length(first_name) between 1 and 40),
  last_name text check (last_name is null or char_length(last_name) between 1 and 40),
  birth_year smallint check (birth_year is null or birth_year between 1940 and 2030),
  birth_date date check (birth_date is null or birth_date between date '1940-01-01' and current_date),
  updated_at timestamptz not null default now()
);
alter table public.profile_private enable row level security;
drop policy if exists "interessato o Direttivo" on public.profile_private;
create policy "interessato o Direttivo" on public.profile_private for all
  using (id = auth.uid() or is_direttivo())
  with check (id = auth.uid() or is_direttivo());
revoke all on public.profile_private from anon;
grant select, insert, update on public.profile_private to authenticated;

-- I dati già inseriti passano nella tabella nuova; da profiles spariscono.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'profiles' and column_name = 'first_name') then
    insert into public.profile_private (id, first_name, last_name, birth_year, birth_date)
    select id, first_name, last_name, birth_year, birth_date from public.profiles
    where first_name is not null or last_name is not null or birth_year is not null
       or birth_date is not null
    on conflict (id) do nothing;
  end if;
end $$;
alter table public.profiles
  drop column if exists first_name,
  drop column if exists last_name,
  drop column if exists birth_year,
  drop column if exists birth_date;

-- Registrazione: come nella 0022, ma i dati anagrafici vanno nella tabella riservata.
create or replace function public.complete_registration(
  p_first_name text,
  p_last_name text,
  p_birth_year int,
  p_display_name text,
  p_motto text,
  p_teams text[],
  p_direttivo boolean,
  p_direttivo_password text,
  p_direttivo_roles text[],
  p_field_position text,
  p_shirt_number int,
  p_platform text,
  p_face jsonb
) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  v_teams text[];
  v_role club_role;
  v_done timestamptz;
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  -- Chi è già entrato nel club non ripassa di qui (squadre e ruolo li cambia il Direttivo).
  -- Il primo Direttivo, nominato dall'editor SQL prima di registrarsi, invece completa.
  select club_role, registration_completed_at into v_role, v_done from profiles where id = uid;
  if v_role is null then
    raise exception 'Profilo non trovato';
  end if;
  if v_role <> 'pending' and v_done is not null then
    raise exception 'Sei già nel club: i tuoi dati si cambiano dalle Impostazioni';
  end if;
  if coalesce(btrim(p_first_name), '') = '' or char_length(btrim(p_first_name)) > 40 then
    raise exception 'Nome non valido';
  end if;
  if coalesce(btrim(p_last_name), '') = '' or char_length(btrim(p_last_name)) > 40 then
    raise exception 'Cognome non valido';
  end if;
  if p_birth_year is null
     or p_birth_year not between 1940 and extract(year from now())::int - 8 then
    raise exception 'Anno di nascita non valido';
  end if;
  if coalesce(btrim(p_display_name), '') = '' or char_length(btrim(p_display_name)) > 14 then
    raise exception 'Nome sulla carta non valido (massimo 14 caratteri)';
  end if;
  if p_motto is not null and char_length(p_motto) > 80 then
    raise exception 'Motto troppo lungo (massimo 80 caratteri)';
  end if;
  if p_shirt_number is not null and p_shirt_number not between 1 and 99 then
    raise exception 'Numero di maglia non valido';
  end if;
  if p_field_position is not null and char_length(p_field_position) > 40 then
    raise exception 'Ruolo in campo non valido';
  end if;
  if p_face is not null and pg_column_size(p_face) > 16384 then
    raise exception 'Volto non valido';
  end if;
  -- Milan AC prima, senza doppioni.
  v_teams := array(select distinct t from unnest(coalesce(p_teams, '{}')) t order by t desc);
  if cardinality(v_teams) = 0 or not (v_teams <@ array['milanac', 'futuro']) then
    raise exception 'Squadra non valida';
  end if;
  if p_direttivo then
    if p_direttivo_roles is null or cardinality(p_direttivo_roles) = 0 then
      raise exception 'Scegli almeno un ruolo nel Direttivo';
    end if;
    if not direttivo_password_ok(p_direttivo_password) then
      return 'password_errata';
    end if;
  elsif cardinality(v_teams) > 1 then
    raise exception 'Un giocatore sta in una sola squadra';
  end if;

  insert into profile_private (id, first_name, last_name, birth_year, updated_at)
  values (uid, btrim(p_first_name), btrim(p_last_name), p_birth_year, now())
  on conflict (id) do update
    set first_name = excluded.first_name, last_name = excluded.last_name,
        birth_year = excluded.birth_year, updated_at = now();
  perform set_config('milanac.registration', '1', true);
  update profiles set
    display_name = btrim(p_display_name),
    motto = nullif(btrim(coalesce(p_motto, '')), ''),
    teams = v_teams,
    requested_role = case when p_direttivo then 'direttivo' else 'giocatore' end::club_role,
    direttivo_roles = case when p_direttivo then p_direttivo_roles else '{}' end,
    field_position = p_field_position,
    shirt_number = p_shirt_number,
    platform = p_platform,
    face = p_face,
    overall = coalesce(overall, 60),
    registration_completed_at = now()
  where id = uid;
  return 'ok';
end $$;
revoke all on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb) from public, anon;
grant execute on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb) to authenticated;

-- ---------------------------------------------------------------- 7) nuovo ingresso
-- Chiunque abbia l'app può registrarsi ed entrare accettando il regolamento: il Direttivo lo
-- sa subito (messaggio nella Sala Direttivo, che manda anche la notifica) e se non lo conosce
-- lo toglie dalla Rosa.
create or replace function public.on_member_joined() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ch uuid := (select id from channels where slug = 'direttivo');
  vero text;
  squadre text;
begin
  if ch is null then return new; end if;
  select nullif(btrim(concat_ws(' ', pp.first_name, pp.last_name)), '') into vero
  from profile_private pp where pp.id = new.id;
  select string_agg(team_name(t), ' e ') into squadre from unnest(new.teams) t;
  insert into messages (channel_id, author_id, kind, body, meta)
  values (ch, new.id, 'system',
          left('Nuovo ingresso: ' || coalesce(nullif(btrim(new.display_name), ''), 'senza nome')
               || coalesce(' (' || vero || ')', '')
               || ' · ' || case when new.club_role = 'direttivo' then 'Direttivo' else 'Giocatore' end
               || coalesce(' · ' || squadre, '')
               || coalesce(' · ' || nullif(btrim(new.field_position), ''), '')
               || '. Se non lo conoscete, toglietelo dalla Rosa.', 2000),
          jsonb_build_object('type', 'new_member', 'member', new.id));
  return new;
end $$;
drop trigger if exists member_joined on public.profiles;
create trigger member_joined after update of club_role on public.profiles
  for each row when (old.club_role = 'pending' and new.club_role <> 'pending')
  execute function public.on_member_joined();

-- ---------------------------------------------------------------- 8) tempo reale
do $$
declare t text;
begin
  foreach t in array array['tournament_standings', 'news', 'club_links', 'rules_versions',
                           'profile_private'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
