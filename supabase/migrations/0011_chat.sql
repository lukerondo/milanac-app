-- Chat a canali: MILANAC Main, Presenze, Fantacalcio, Tattiche & Schemi.

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,30}$'),
  name text not null,
  description text,
  icon text not null default 'chat',
  sort_order int not null default 0
);
alter table public.channels enable row level security;
drop policy if exists "lettura membri" on public.channels;
create policy "lettura membri" on public.channels for select using (is_member());
drop policy if exists "scrittura direttivo" on public.channels;
create policy "scrittura direttivo" on public.channels for all
  using (is_direttivo()) with check (is_direttivo());

insert into public.channels (slug, name, description, icon, sort_order) values
  ('main', 'MILANAC Main', 'Il canale di tutto il club', 'forum', 0),
  ('presenze', 'Presenze', 'Ritardi e assenze arrivano qui in automatico', 'presenze', 1),
  ('fantacalcio', 'Fantacalcio', 'Aste, scambi e sfottò', 'fantacalcio', 2),
  ('tattiche', 'Tattiche & Schemi', 'Idee, schemi e video', 'tattiche', 3)
on conflict (slug) do nothing;

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels on delete cascade,
  author_id uuid default auth.uid() references public.profiles on delete set null,
  kind text not null default 'user' check (kind in ('user', 'system')),
  body text check (body is null or char_length(body) <= 2000),
  image_path text,
  meta jsonb,
  created_at timestamptz not null default now(),
  check (coalesce(btrim(body), '') <> '' or image_path is not null)
);
create index if not exists messages_channel_created_idx on public.messages (channel_id, created_at desc);

alter table public.messages enable row level security;
drop policy if exists "lettura membri" on public.messages;
create policy "lettura membri" on public.messages for select using (is_member());
drop policy if exists "membri scrivono" on public.messages;
create policy "membri scrivono" on public.messages for insert
  with check (is_member() and author_id = auth.uid() and kind = 'user');
drop policy if exists "autore o direttivo eliminano" on public.messages;
create policy "autore o direttivo eliminano" on public.messages for delete
  using (is_direttivo() or (author_id = auth.uid() and kind = 'user'));

-- Canali silenziati (niente notifiche) e ultimo messaggio letto, per utente.
create table if not exists public.channel_mutes (
  channel_id uuid not null references public.channels on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  primary key (channel_id, user_id)
);
alter table public.channel_mutes enable row level security;
drop policy if exists "propri" on public.channel_mutes;
create policy "propri" on public.channel_mutes for all
  using (user_id = auth.uid()) with check (user_id = auth.uid() and is_member());

create table if not exists public.channel_reads (
  channel_id uuid not null references public.channels on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);
alter table public.channel_reads enable row level security;
drop policy if exists "propri" on public.channel_reads;
create policy "propri" on public.channel_reads for all
  using (user_id = auth.uid()) with check (user_id = auth.uid() and is_member());

-- Riepilogo per la lista dei canali: non letti (max 99) e ultimo messaggio.
create or replace function public.chat_overview()
returns table (channel_id uuid, unread int, last_body text, last_author text, last_kind text,
               last_has_image boolean, last_at timestamptz)
language sql stable set search_path = public as $$
  select c.id,
         (select count(*) from (
            select 1 from messages m
            where m.channel_id = c.id
              and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz)
              and m.author_id is distinct from auth.uid()
            limit 99) u)::int,
         lm.body, lm.author, lm.kind, lm.image_path is not null, lm.created_at
  from channels c
  left join channel_reads r on r.channel_id = c.id and r.user_id = auth.uid()
  left join lateral (
    select m.body, m.kind, m.image_path, m.created_at, p.display_name as author
    from messages m left join profiles p on p.id = m.author_id
    where m.channel_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  order by c.sort_order
$$;
revoke all on function public.chat_overview() from public, anon;
grant execute on function public.chat_overview() to authenticated;

-- Foto nella chat: bucket privato, ognuno carica nella propria cartella.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat', 'chat', false, 5 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
drop policy if exists "foto chat leggibili dai membri" on storage.objects;
create policy "foto chat leggibili dai membri" on storage.objects for select
  using (bucket_id = 'chat' and is_member());
drop policy if exists "foto chat proprie" on storage.objects;
create policy "foto chat proprie" on storage.objects for insert
  with check (bucket_id = 'chat' and is_member() and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "foto chat eliminabili" on storage.objects;
create policy "foto chat eliminabili" on storage.objects for delete
  using (bucket_id = 'chat' and (is_direttivo() or (storage.foldername(name))[1] = auth.uid()::text));

-- Ogni nuovo messaggio: notifica ai membri (esclusi l'autore e chi ha silenziato il canale).
create or replace function public.on_message_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_push(jsonb_build_object('kind', 'chat_message', 'id', new.id));
  return new;
end $$;
drop trigger if exists message_created on public.messages;
create trigger message_created after insert on public.messages
  for each row execute function public.on_message_created();

-- Ritardi e assenze di oggi (o dei prossimi giorni) finiscono nel canale Presenze.
create or replace function public.on_attendance_changed() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ch uuid := (select id from channels where slug = 'presenze');
  who text := (select display_name from profiles where id = new.player_id);
  today date := (now() at time zone 'Europe/Rome')::date;
  quando text;
  testo text;
begin
  if ch is null or new.date < today then return new; end if;
  if tg_op = 'UPDATE' and new.status = old.status
     and new.arrival_time = old.arrival_time
     and new.note is not distinct from old.note then
    return new;
  end if;
  quando := case
    when new.date = today then 'stasera'
    when new.date = today + 1 then 'domani'
    else 'il ' || to_char(new.date, 'DD/MM') end;
  testo := case new.status
    when 'ritardo' then who || ' ' || quando || ' arriva in ritardo, alle ' || to_char(new.arrival_time, 'HH24:MI')
    when 'assente' then who || ' ' || quando || ' è assente'
    -- "presente" si annuncia solo se prima aveva segnato ritardo o assenza
    when 'presente' then case when tg_op = 'UPDATE' and old.status <> 'presente'
                              then who || ' ' || quando || ' alla fine ci sarà' end
  end;
  if testo is null then return new; end if;
  if coalesce(btrim(new.note), '') <> '' then testo := testo || ' · ' || new.note; end if;
  insert into messages (channel_id, author_id, kind, body, meta)
  values (ch, new.player_id, 'system', testo,
          jsonb_build_object('type', 'attendance', 'status', new.status, 'date', new.date));
  return new;
end $$;
drop trigger if exists attendance_to_chat on public.attendance;
create trigger attendance_to_chat after insert or update on public.attendance
  for each row execute function public.on_attendance_changed();

-- Messaggi in tempo reale nell'app.
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;
