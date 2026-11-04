-- Allineamento al regolamento ufficiale (novembre 2026).
--  1) Le serate del club sono dal lunedì al venerdì, dalle 21:30 alle 23:30 (ora italiana):
--     sabato e domenica non c'è l'allenamento, quindi niente promemoria delle 18:00 né
--     assenze automatiche delle 18:30, a meno che il Direttivo non metta un evento in
--     calendario (una partita di torneo, un'amichevole): allora vale come una serata normale,
--     per chi gioca nella squadra dell'evento. La scadenza delle 18:30 resta; un evento messo
--     in calendario (o spostato su quel giorno) dopo le 18:30 non fa assenze.
--  2) I convocati si presentano in party 30 minuti prima della partita: il promemoria
--     automatico "un'ora prima" diventa "trenta minuti prima" (tutti in party); quello dei
--     dieci minuti prima (tutti in lobby) resta.
--  3) Le etichette del Direttivo seguono l'organigramma del regolamento: Presidente,
--     Fondatore, Capitano, Vice-capitano e i responsabili (Comunicazioni e Marketing,
--     Tecnico/Tattico, Reclutamento, Tornei e Amichevoli, Presenze, IT). I poteri restano
--     gli stessi per tutti.

-- ---------------------------------------------------------------- 1) serate dal lunedì al venerdì
-- Quando l'evento è stato messo a quell'ora in calendario: alla creazione (created_at) e di
-- nuovo ogni volta che cambia l'inizio. Gli eventi che ci sono già partono da created_at.
-- L'app salva sempre anche starts_at: conta solo se cambia davvero. Chi scrive la colonna a
-- mano non la cambia.
alter table public.events add column if not exists scheduled_at timestamptz;
update public.events set scheduled_at = created_at where scheduled_at is null;
alter table public.events
  alter column scheduled_at set default now(),
  alter column scheduled_at set not null;

-- app_now() è now() in produzione (nei test l'ora si fissa con milanac.now).
create or replace function public.events_scheduled_at() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.scheduled_at := new.created_at;
  elsif new.starts_at is distinct from old.starts_at then
    new.scheduled_at := app_now();
  else
    new.scheduled_at := old.scheduled_at;
  end if;
  return new;
end $$;
drop trigger if exists events_scheduled_at on public.events;
create trigger events_scheduled_at before insert or update of starts_at, scheduled_at
  on public.events for each row execute function public.events_scheduled_at();

-- C'è la serata del giorno p_day (italiano) per chi gioca in p_teams? Dal lunedì al venerdì
-- sempre (l'allenamento delle 21:30, se non c'è altro); sabato e domenica solo con un evento
-- in calendario per una di quelle squadre (o per tutti). Le riunioni non chiedono presenze.
-- Con p_before contano solo gli eventi messi in calendario a quell'ora prima di quell'istante
-- (scheduled_at: creati o spostati prima).
create or replace function public.club_evening(p_day date, p_teams text[],
                                               p_before timestamptz default null)
returns boolean
language sql stable set search_path = public as $$
  select extract(isodow from p_day) between 1 and 5
      or exists (select 1 from events e
                 where e.type <> 'riunione'
                   and (e.starts_at at time zone 'Europe/Rome')::date = p_day
                   and (e.team is null or e.team = any(p_teams))
                   and (p_before is null or e.scheduled_at < p_before))
$$;

-- Come nella 0017, ma solo nei giorni con la serata e solo per chi ce l'ha.
create or replace function public.attendance_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  t timestamp := app_now() at time zone 'Europe/Rome';
  today date := t::date;
  users uuid[];
begin
  -- Sabato e domenica senza eventi non c'è la serata: niente promemoria né assenze. Il
  -- giorno non si segna, così un evento messo in calendario più tardi conta ancora.
  if not club_evening(today, array['milanac', 'futuro']) then
    return;
  end if;
  -- 18:00: promemoria a chi non ha ancora risposto per stasera (nel fine settimana solo a
  -- chi gioca nella squadra dell'evento).
  if t::time >= time '18:00' and t::time < time '18:30'
     and not exists (select 1 from daily_jobs where day = today and job = 'promemoria') then
    insert into daily_jobs (day, job) values (today, 'promemoria');
    select coalesce(array_agg(p.id), '{}') into users
    from profiles p
    where p.active and p.club_role <> 'pending'
      and club_evening(today, p.teams)
      and not exists (select 1 from attendance a where a.player_id = p.id and a.date = today);
    if cardinality(users) > 0 then
      perform notify_push(jsonb_build_object(
        'kind', 'attendance_reminder', 'day', today, 'users', to_jsonb(users)));
    end if;
  end if;
  -- 18:30: chi non ha risposto risulta assente (assenza automatica, correggibile dal Direttivo).
  -- Un evento del fine settimana messo in calendario (o spostato su oggi) dopo la scadenza
  -- non fa assenze: nessuno ha potuto rispondere.
  if t::time >= time '18:30'
     and club_evening(today, array['milanac', 'futuro'], attendance_deadline(today))
     and not exists (select 1 from daily_jobs where day = today and job = 'assenze') then
    insert into daily_jobs (day, job) values (today, 'assenze');
    with ins as (
      insert into attendance (player_id, date, status, auto)
      select p.id, today, 'assente', true
      from profiles p
      where p.active and p.club_role <> 'pending'
        and club_evening(today, p.teams, attendance_deadline(today))
        and not exists (select 1 from attendance a where a.player_id = p.id and a.date = today)
      returning player_id
    )
    select coalesce(array_agg(player_id), '{}') into users from ins;
    if cardinality(users) > 0 then
      perform notify_push(jsonb_build_object(
        'kind', 'attendance_auto_absent', 'day', today, 'users', to_jsonb(users)));
    end if;
  end if;
end $$;
revoke all on function public.attendance_tick() from public, anon, authenticated;

-- ---------------------------------------------------------------- 2) in party 30 minuti prima
-- I promemoria automatici diventano "party" (trenta minuti prima) e "lobby" (dieci minuti
-- prima); quelli "ora" già partiti contano come "party", così non si ripetono.
alter table public.event_reminders drop constraint if exists event_reminders_kind_check;
update public.event_reminders set kind = 'party' where kind = 'ora';
alter table public.event_reminders add constraint event_reminders_kind_check
  check (kind in ('party', 'lobby', 'chiamata'));

-- Ogni minuto (pg_cron, già programmato dalla 0031): gli avvisi delle partite che iniziano
-- entro mezz'ora.
create or replace function public.match_reminders_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  now_ timestamptz := app_now();
  e record;
begin
  for e in
    select id, starts_at, created_at from events
    where type in ('torneo', 'amichevole')
      and starts_at > now_ and starts_at <= now_ + interval '30 minutes'
  loop
    -- Trenta minuti prima: tutti in party, come da regolamento. Solo se la partita era già
    -- in calendario (appena creata ha già avuto la sua notifica) e se manca ancora abbastanza
    -- al richiamo in lobby.
    if e.starts_at - interval '30 minutes' <= now_
       and e.starts_at > now_ + interval '15 minutes'
       and e.created_at < e.starts_at - interval '30 minutes' then
      insert into event_reminders (event_id, kind, starts_at) values (e.id, 'party', e.starts_at)
      on conflict do nothing;
      if found then
        perform notify_push(jsonb_build_object('kind', 'match_reminder', 'id', e.id, 'when', 'party'));
      end if;
    end if;
    -- Dieci minuti prima: tutti in lobby.
    if e.starts_at - interval '10 minutes' <= now_ then
      insert into event_reminders (event_id, kind, starts_at) values (e.id, 'lobby', e.starts_at)
      on conflict do nothing;
      if found then
        perform notify_push(jsonb_build_object('kind', 'match_reminder', 'id', e.id, 'when', 'lobby'));
      end if;
    end if;
  end loop;
end $$;
revoke all on function public.match_reminders_tick() from public, anon, authenticated;

-- ---------------------------------------------------------------- 3) ruoli del Direttivo
-- L'organigramma del regolamento, nell'ordine in cui si mostra.
create or replace function public.direttivo_role_order() returns text[]
language sql immutable as $$
  select array['presidente', 'fondatore', 'capitano', 'vicecapitano', 'comunicazione',
               'tecnico', 'reclutamento', 'tornei', 'presenze', 'it']
$$;

-- Come si legge un ruolo (stesse etichette dell'app).
create or replace function public.direttivo_role_label(p_role text) returns text
language sql immutable as $$
  select case p_role
    when 'presidente' then 'Presidente'
    when 'fondatore' then 'Fondatore'
    when 'capitano' then 'Capitano'
    when 'vicecapitano' then 'Vice-capitano'
    when 'comunicazione' then 'Resp. Comunicazioni e Marketing'
    when 'tecnico' then 'Resp. Tecnico/Tattico'
    when 'reclutamento' then 'Resp. Reclutamento'
    when 'tornei' then 'Resp. Tornei e Amichevoli'
    when 'presenze' then 'Resp. Presenze'
    when 'it' then 'Resp. IT'
    else initcap(p_role)
  end
$$;

-- Le etichette di prima diventano quelle nuove (Reclutatore → Resp. Reclutamento,
-- Organizzatore → Resp. Tornei e Amichevoli; Gestore sparisce), senza doppioni e
-- nell'ordine dell'organigramma. Un nome sconosciuto resta (e lo ferma il controllo).
create or replace function public.direttivo_roles_normalized(p_roles text[]) returns text[]
language sql immutable as $$
  select coalesce(array_agg(r order by coalesce(array_position(direttivo_role_order(), r), 99), r),
                  '{}')
  from (
    select distinct case v when 'reclutatore' then 'reclutamento'
                           when 'organizzatore' then 'tornei'
                           else v end as r
    from unnest(coalesce(p_roles, '{}')) v
    where v <> 'gestore'
  ) x
$$;

alter table public.profiles drop constraint if exists profiles_direttivo_roles_check;
update public.profiles set direttivo_roles = direttivo_roles_normalized(direttivo_roles)
  where direttivo_roles is distinct from direttivo_roles_normalized(direttivo_roles);
alter table public.profiles add constraint profiles_direttivo_roles_check
  check (direttivo_roles <@ array['presidente', 'fondatore', 'capitano', 'vicecapitano',
                                  'comunicazione', 'tecnico', 'reclutamento', 'tornei',
                                  'presenze', 'it']);

-- Le app di prima mandano ancora i nomi vecchi (registrazione, Rosa): si traducono qui,
-- invece di rifiutare il salvataggio.
create or replace function public.direttivo_roles_before_write() returns trigger
language plpgsql as $$
begin
  new.direttivo_roles := direttivo_roles_normalized(new.direttivo_roles);
  return new;
end $$;
drop trigger if exists direttivo_roles_before_write on public.profiles;
create trigger direttivo_roles_before_write before insert or update of direttivo_roles
  on public.profiles for each row execute function public.direttivo_roles_before_write();

-- L'avviso nella Sala Direttivo usa le etichette vere, nell'ordine dell'organigramma.
create or replace function public.on_direttivo_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ch uuid := (select id from channels where slug = 'direttivo');
  chi text := (select display_name from profiles where id = auth.uid());
  etichette text;
begin
  if ch is null or old.club_role = 'pending' or new.club_role = 'pending' then
    return new;
  end if;
  if new.club_role = 'direttivo' then
    select string_agg(direttivo_role_label(r), ', '
                      order by array_position(direttivo_role_order(), r))
      into etichette from unnest(new.direttivo_roles) r;
    insert into messages (channel_id, author_id, kind, body, meta)
    values (ch, auth.uid(), 'system',
            left(new.display_name || ' è entrato nel Direttivo'
                 || coalesce(' (' || etichette || ')', '')
                 || coalesce(' · nominato da ' || chi, '') || '.', 2000),
            jsonb_build_object('type', 'direttivo', 'member', new.id, 'role', 'direttivo'));
  elsif old.club_role = 'direttivo' then
    insert into messages (channel_id, author_id, kind, body, meta)
    values (ch, auth.uid(), 'system',
            left(new.display_name || ' non fa più parte del Direttivo'
                 || coalesce(' · deciso da ' || chi, '') || '.', 2000),
            jsonb_build_object('type', 'direttivo', 'member', new.id, 'role', new.club_role));
  end if;
  return new;
end $$;
