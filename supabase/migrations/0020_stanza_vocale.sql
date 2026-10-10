-- Fase 5 (ottobre 2026): stanza vocale in ogni chat (Agora).
-- Una stanza per canale: chi la apre avvisa i membri del canale, gli altri entrano con un
-- tocco; la stanza si chiude quando esce l'ultimo. Le sessioni registrano i minuti usati
-- (il piano gratuito di Agora dà 10.000 minuti-partecipante al mese): il Direttivo li vede.
-- I biglietti d'ingresso (token Agora) li genera la funzione Edge "voice-token".

-- ---------------------------------------------------------------- 1) stanze e sessioni
create table if not exists public.voice_rooms (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels on delete cascade,
  opened_by uuid references public.profiles on delete set null,
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);
-- Una sola stanza aperta per canale.
create unique index if not exists voice_rooms_open_idx
  on public.voice_rooms (channel_id) where closed_at is null;

create table if not exists public.voice_sessions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.voice_rooms on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  agora_uid bigint,                                   -- assegnato da Agora all'ingresso
  joined_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),    -- l'app lo rinnova ogni minuto
  left_at timestamptz,
  muted boolean not null default false
);
create index if not exists voice_sessions_room_idx on public.voice_sessions (room_id) where left_at is null;
create unique index if not exists voice_sessions_active_idx
  on public.voice_sessions (room_id, user_id) where left_at is null;
create index if not exists voice_sessions_month_idx on public.voice_sessions (joined_at);

-- Chi vede un canale (stessa regola della policy dei canali, usabile dentro le funzioni).
create or replace function public.can_see_channel(p_channel uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from channels c
    where c.id = p_channel and is_member()
      and (not c.direttivo_only or is_direttivo())
      and (c.team is null or is_direttivo() or in_team(c.team)))
$$;

alter table public.voice_rooms enable row level security;
drop policy if exists "lettura membri" on public.voice_rooms;
create policy "lettura membri" on public.voice_rooms for select
  using (can_see_channel(channel_id));
alter table public.voice_sessions enable row level security;
drop policy if exists "lettura membri" on public.voice_sessions;
create policy "lettura membri" on public.voice_sessions for select
  using (exists (select 1 from voice_rooms r where r.id = room_id and can_see_channel(r.channel_id)));
-- Si scrive solo tramite le funzioni qui sotto.

-- ---------------------------------------------------------------- 2) aprire, entrare, uscire
-- Apre la stanza del canale (o entra in quella già aperta) e avvisa i membri la prima volta.
create or replace function public.open_voice_room(p_channel uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  room uuid;
  created boolean := false;
begin
  if auth.uid() is null or not can_see_channel(p_channel) then
    raise exception 'Canale non disponibile';
  end if;
  select id into room from voice_rooms where channel_id = p_channel and closed_at is null;
  if room is null then
    insert into voice_rooms (channel_id, opened_by, opened_at)
    values (p_channel, auth.uid(), app_now()) returning id into room;
    created := true;
  end if;
  perform join_voice_room(room, null);
  if created then
    perform notify_push(jsonb_build_object('kind', 'voice_room', 'id', room));
  end if;
  return room;
end $$;

-- Entra nella stanza (o aggiorna la propria sessione); restituisce l'id della sessione.
create or replace function public.join_voice_room(p_room uuid, p_agora_uid bigint default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  ch uuid;
  sess uuid;
begin
  select channel_id into ch from voice_rooms where id = p_room and closed_at is null;
  if ch is null or auth.uid() is null or not can_see_channel(ch) then
    raise exception 'Stanza chiusa o non disponibile';
  end if;
  select id into sess from voice_sessions
  where room_id = p_room and user_id = auth.uid() and left_at is null;
  if sess is null then
    insert into voice_sessions (room_id, user_id, agora_uid, joined_at, heartbeat_at)
    values (p_room, auth.uid(), p_agora_uid, app_now(), app_now()) returning id into sess;
  else
    update voice_sessions
    set heartbeat_at = app_now(), agora_uid = coalesce(p_agora_uid, agora_uid)
    where id = sess;
  end if;
  return sess;
end $$;

-- Segno di vita (ogni minuto dall'app) con lo stato del microfono.
create or replace function public.voice_heartbeat(p_session uuid, p_muted boolean default false)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update voice_sessions set heartbeat_at = app_now(), muted = p_muted
  where id = p_session and user_id = auth.uid() and left_at is null;
end $$;

-- Esce dalla stanza; se era l'ultimo, la stanza si chiude.
create or replace function public.leave_voice_room(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare room uuid;
begin
  update voice_sessions set left_at = app_now()
  where id = p_session and user_id = auth.uid() and left_at is null
  returning room_id into room;
  if room is not null and not exists (
       select 1 from voice_sessions where room_id = room and left_at is null) then
    update voice_rooms set closed_at = app_now() where id = room and closed_at is null;
  end if;
end $$;

-- Ogni minuto (pg_cron): chi non dà segni di vita da 3 minuti è uscito (app chiusa,
-- telefono spento) e le stanze vuote si chiudono.
create or replace function public.voice_tick() returns void
language plpgsql security definer set search_path = public as $$
begin
  update voice_sessions set left_at = heartbeat_at
  where left_at is null and heartbeat_at < app_now() - interval '3 minutes';
  update voice_rooms r set closed_at = app_now()
  where r.closed_at is null
    and r.opened_at < app_now() - interval '2 minutes'
    and not exists (select 1 from voice_sessions s where s.room_id = r.id and s.left_at is null);
end $$;
revoke all on function public.voice_tick() from public, anon, authenticated;
do $$ begin
  perform cron.schedule('stanze-vocali', '* * * * *', 'select public.voice_tick()');
end $$;

-- Minuti-partecipante usati in un mese (predefinito: questo mese), per la Sala Direttivo.
create or replace function public.voice_minutes(p_month date default null) returns int
language sql stable security definer set search_path = public as $$
  select case when not is_member() then 0 else coalesce(sum(
    ceil(extract(epoch from (coalesce(s.left_at, app_now()) - s.joined_at)) / 60.0)), 0)::int end
  from voice_sessions s
  where date_trunc('month', s.joined_at at time zone 'Europe/Rome')
        = date_trunc('month', coalesce(p_month, (app_now() at time zone 'Europe/Rome')::date)::timestamp)
$$;

revoke all on function public.open_voice_room(uuid) from public, anon;
revoke all on function public.join_voice_room(uuid, bigint) from public, anon;
revoke all on function public.voice_heartbeat(uuid, boolean) from public, anon;
revoke all on function public.leave_voice_room(uuid) from public, anon;
revoke all on function public.voice_minutes(date) from public, anon;
grant execute on function public.open_voice_room(uuid) to authenticated;
grant execute on function public.join_voice_room(uuid, bigint) to authenticated;
grant execute on function public.voice_heartbeat(uuid, boolean) to authenticated;
grant execute on function public.leave_voice_room(uuid) to authenticated;
grant execute on function public.voice_minutes(date) to authenticated;

-- Stanze e partecipanti in tempo reale nell'app.
do $$ begin
  alter publication supabase_realtime add table public.voice_rooms;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.voice_sessions;
exception when duplicate_object then null;
end $$;
