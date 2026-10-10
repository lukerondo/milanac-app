-- Fase 2 (ottobre 2026): Home con Mondo Proclub e Presenze.
-- Presenze a calendario: risposta entro le 18:30 (ora italiana), promemoria alle 18:00 e assenza
-- automatica alle 18:30 con pg_cron; nota obbligatoria per il ritardo; il Direttivo corregge
-- anche dopo la scadenza. Eventi con notifica alla creazione. Canali nuovi (Generale, Milan AC,
-- Milan AC Futuro, Tattiche e Schemi, Comunicazioni, Direttivo). La formazione pubblicata viene
-- annunciata in Comunicazioni. Mondo Proclub: video dei creator proposti dai giocatori e
-- pubblicati dal Direttivo. Notizie sulle console (PlayStation, Xbox) con avviso per piattaforma.

-- ---------------------------------------------------------------- 0) "adesso"
-- Nei test si può fissare l'ora (impostazione di sessione milanac.now); in produzione è now().
create or replace function public.app_now() returns timestamptz
language sql stable as $$
  select coalesce(nullif(current_setting('milanac.now', true), '')::timestamptz, now())
$$;

-- ---------------------------------------------------------------- 1) presenze
alter table public.attendance
  add column if not exists auto boolean not null default false,            -- "assente, non ha risposto"
  add column if not exists set_by uuid references public.profiles on delete set null;  -- chi ha corretto

alter table public.attendance drop constraint if exists attendance_note_check;
alter table public.attendance add constraint attendance_note_check
  check (note is null or char_length(note) <= 200);
-- Il ritardo vuole sempre una nota (motivo); l'assenza no.
alter table public.attendance drop constraint if exists attendance_late_note_check;
alter table public.attendance add constraint attendance_late_note_check
  check (status <> 'ritardo' or coalesce(btrim(note), '') <> '');

-- Le risposte chiudono alle 18:30 italiane del giorno stesso.
create or replace function public.attendance_deadline(p_day date) returns timestamptz
language sql stable as $$
  select (p_day + time '18:30') at time zone 'Europe/Rome'
$$;
create or replace function public.attendance_open(p_day date) returns boolean
language sql stable as $$
  select app_now() < attendance_deadline(p_day)
$$;

-- Chi risponde per sé lo fa solo finché le risposte sono aperte; il Direttivo sempre.
drop policy if exists "proprie presenze" on public.attendance;
create policy "proprie presenze" on public.attendance for all
  using (player_id = auth.uid() and is_member() and attendance_open(attendance.date))
  with check (player_id = auth.uid() and is_member() and attendance_open(attendance.date));

-- Chi scrive per conto di un altro (il Direttivo) resta registrato; una risposta vera
-- (di chiunque) non è più "automatica".
create or replace function public.attendance_before_write() returns trigger
language plpgsql as $$
begin
  new.set_by := case when auth.uid() is not null and auth.uid() <> new.player_id then auth.uid() end;
  if auth.uid() is not null then new.auto := false; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists attendance_before_write on public.attendance;
create trigger attendance_before_write before insert or update on public.attendance
  for each row execute function public.attendance_before_write();

-- Il canale Presenze sparisce: niente più messaggi automatici per ritardi e assenze.
drop trigger if exists attendance_to_chat on public.attendance;
drop function if exists public.on_attendance_changed();

-- ---------------------------------------------------------------- 2) lavori automatici
-- Un segno per ogni lavoro fatto in un giorno, così ogni passaggio avviene una volta sola.
create table if not exists public.daily_jobs (
  day date not null,
  job text not null,
  done_at timestamptz not null default now(),
  primary key (day, job)
);
alter table public.daily_jobs enable row level security;  -- nessuna policy: solo il server

create or replace function public.attendance_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  t timestamp := app_now() at time zone 'Europe/Rome';
  today date := t::date;
  users uuid[];
begin
  -- 18:00: promemoria a chi non ha ancora risposto per stasera.
  if t::time >= time '18:00' and t::time < time '18:30'
     and not exists (select 1 from daily_jobs where day = today and job = 'promemoria') then
    insert into daily_jobs (day, job) values (today, 'promemoria');
    select coalesce(array_agg(p.id), '{}') into users
    from profiles p
    where p.active and p.club_role <> 'pending'
      and not exists (select 1 from attendance a where a.player_id = p.id and a.date = today);
    if cardinality(users) > 0 then
      perform notify_push(jsonb_build_object(
        'kind', 'attendance_reminder', 'day', today, 'users', to_jsonb(users)));
    end if;
  end if;
  -- 18:30: chi non ha risposto risulta assente (assenza automatica, correggibile dal Direttivo).
  if t::time >= time '18:30'
     and not exists (select 1 from daily_jobs where day = today and job = 'assenze') then
    insert into daily_jobs (day, job) values (today, 'assenze');
    with ins as (
      insert into attendance (player_id, date, status, auto)
      select p.id, today, 'assente', true
      from profiles p
      where p.active and p.club_role <> 'pending'
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

-- Ogni minuto (pg_cron, estensione di Supabase): il controllo è leggero e non fa nulla
-- finché non è ora. I dettagli delle esecuzioni si puliscono dopo una settimana.
create extension if not exists pg_cron;
do $$ begin
  perform cron.schedule('presenze', '* * * * *', 'select public.attendance_tick()');
  perform cron.schedule('pulizia-cron', '0 3 * * *',
    'delete from cron.job_run_details where end_time < now() - interval ''7 days''');
end $$;

-- ---------------------------------------------------------------- 3) eventi: notifica alla creazione
create or replace function public.on_event_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_push(jsonb_build_object('kind', 'event', 'id', new.id));
  return new;
end $$;
drop trigger if exists event_created on public.events;
create trigger event_created after insert on public.events
  for each row execute function public.on_event_created();

-- ---------------------------------------------------------------- 4) canali
alter table public.channels
  add column if not exists team text,                                   -- canale di una squadra
  add column if not exists direttivo_writes boolean not null default false;  -- scrive solo il Direttivo
alter table public.channels drop constraint if exists channels_team_check;
alter table public.channels add constraint channels_team_check
  check (team is null or team in ('milanac', 'futuro'));

delete from public.channels where slug in ('presenze', 'fantacalcio');
update public.channels
  set name = 'Generale', description = 'La chat di tutto il club', sort_order = 0
  where slug = 'main';
insert into public.channels (slug, name, description, icon, sort_order, team, direttivo_writes) values
  ('milanac', 'Milan AC', 'La chat della prima squadra', 'team', 1, 'milanac', false),
  ('futuro', 'Milan AC Futuro', 'La chat del Futuro', 'team', 2, 'futuro', false),
  ('comunicazioni', 'Comunicazioni', 'Avvisi ufficiali del Direttivo: formazioni, eventi, regolamento',
   'campaign', 4, null, true)
on conflict (slug) do update
  set name = excluded.name, description = excluded.description, icon = excluded.icon,
      sort_order = excluded.sort_order, team = excluded.team, direttivo_writes = excluded.direttivo_writes;
update public.channels set sort_order = 3 where slug = 'tattiche';
update public.channels set sort_order = 10 where slug = 'direttivo';

-- Chi è collegato gioca in questa squadra?
create or replace function public.in_team(p_team text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and p_team = any(teams))
$$;

-- I canali di squadra li vede chi ci gioca (il Direttivo tutti); quello riservato solo il Direttivo.
drop policy if exists "lettura membri" on public.channels;
create policy "lettura membri" on public.channels for select
  using (is_member() and (not direttivo_only or is_direttivo())
         and (team is null or is_direttivo() or in_team(team)));

-- Si scrive solo nei canali visibili; in Comunicazioni (e negli avvisi) solo il Direttivo.
drop policy if exists "membri scrivono" on public.messages;
create policy "membri scrivono" on public.messages for insert
  with check (
    is_member() and author_id = auth.uid() and kind = 'user'
    and exists (select 1 from channels c where c.id = channel_id
                and (not c.direttivo_writes or is_direttivo()))
    and (meta is null or meta->>'type' is distinct from 'announcement' or is_direttivo())
  );

-- La formazione annunciata in Comunicazioni non manda una seconda notifica:
-- ogni giocatore riceve già la sua (titolare o panchina).
create or replace function public.on_message_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'system' and new.meta->>'type' = 'formation' then return new; end if;
  perform notify_push(jsonb_build_object('kind', 'chat_message', 'id', new.id));
  return new;
end $$;

-- ---------------------------------------------------------------- 5) formazione pubblicata → Comunicazioni
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
  select string_agg(s.label || ' ' || coalesce(p.display_name, '—'), ', ' order by s.slot_index)
    into titolari
  from formation_slots s left join profiles p on p.id = s.player_id
  where s.formation_id = new.id and s.player_id is not null;
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

-- ---------------------------------------------------------------- 6) Mondo Proclub: video dei creator
-- I "video delle build" diventano i video di Mondo Proclub: i giocatori li propongono,
-- il Direttivo li pubblica.
alter table public.shared_links drop constraint if exists shared_links_category_check;
update public.shared_links set category = 'video' where category = 'build';
alter table public.shared_links add constraint shared_links_category_check
  check (category in ('musica', 'video'));

alter table public.shared_links
  add column if not exists status text not null default 'pubblicato',
  add column if not exists published_by uuid references public.profiles on delete set null,
  add column if not exists published_at timestamptz;
alter table public.shared_links drop constraint if exists shared_links_status_check;
alter table public.shared_links add constraint shared_links_status_check
  check (status in ('proposto', 'pubblicato'));

create or replace function public.shared_links_before_write() returns trigger
language plpgsql as $$
begin
  if new.category <> 'video' then
    new.status := 'pubblicato';
  elsif auth.uid() is not null and not is_direttivo() then
    -- un giocatore può solo proporre (e ritoccare la propria proposta)
    new.status := 'proposto';
    new.published_by := null;
    new.published_at := null;
  elsif new.status = 'pubblicato' and (tg_op = 'INSERT' or old.status <> 'pubblicato') then
    new.published_by := coalesce(auth.uid(), new.published_by);
    new.published_at := now();
  end if;
  return new;
end $$;
drop trigger if exists shared_links_before_write on public.shared_links;
create trigger shared_links_before_write before insert or update on public.shared_links
  for each row execute function public.shared_links_before_write();

-- Le proposte le vedono solo chi le ha fatte e il Direttivo.
drop policy if exists "lettura membri" on public.shared_links;
create policy "lettura membri" on public.shared_links for select
  using (is_member() and (status = 'pubblicato' or created_by = auth.uid() or is_direttivo()));

-- Proposta → avviso al Direttivo; pubblicazione → avviso a chi l'ha proposto.
create or replace function public.on_shared_link_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.category <> 'video' then return new; end if;
  if tg_op = 'INSERT' and new.status = 'proposto' then
    perform notify_push(jsonb_build_object('kind', 'video_proposed', 'id', new.id));
  elsif new.status = 'pubblicato' and (tg_op = 'INSERT' or old.status <> 'pubblicato') then
    perform notify_push(jsonb_build_object('kind', 'video_published', 'id', new.id));
  end if;
  return new;
end $$;
drop trigger if exists shared_link_changed on public.shared_links;
create trigger shared_link_changed after insert or update on public.shared_links
  for each row execute function public.on_shared_link_changed();

-- ---------------------------------------------------------------- 7) notizie: console e avvisi
alter table public.news drop constraint if exists news_category_check;
alter table public.news add constraint news_category_check
  check (category in ('tornei', 'aggiornamenti', 'ultimate_team', 'pro_clubs', 'console'));
alter table public.news add column if not exists platform text;
alter table public.news drop constraint if exists news_platform_check;
alter table public.news add constraint news_platform_check
  check (platform is null or platform in ('ps5', 'xbox'));

-- Nuovo aggiornamento di FC 27 (a tutti) o di una console (a chi la usa): al massimo un avviso
-- ogni 12 ore per tipo, così la stessa notizia ripresa da più fonti non si ripete.
create or replace function public.on_news_inserted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.category not in ('aggiornamenti', 'console') then return new; end if;
  if new.category = 'console' and new.platform is null then return new; end if;
  if new.published_at < now() - interval '3 days' then return new; end if;
  if exists (select 1 from news n
             where n.id <> new.id and n.category = new.category
               and n.platform is not distinct from new.platform
               and n.notified_at > now() - interval '12 hours') then
    return new;
  end if;
  update news set notified_at = now() where id = new.id;
  perform notify_push(jsonb_build_object('kind', 'news', 'id', new.id));
  return new;
end $$;
drop trigger if exists news_inserted on public.news;
create trigger news_inserted after insert on public.news
  for each row execute function public.on_news_inserted();

-- ---------------------------------------------------------------- 8) aggiornamenti in tempo reale
do $$ begin
  alter publication supabase_realtime add table public.events;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.shared_links;
exception when duplicate_object then null;
end $$;
