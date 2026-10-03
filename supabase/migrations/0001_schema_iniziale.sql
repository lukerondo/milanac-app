-- MILANAC Pro Club – schema iniziale
-- Ruoli: direttivo (gestisce tutto), giocatore (legge + proprie presenze), pending (in attesa di approvazione)

create type club_role as enum ('direttivo', 'giocatore', 'pending');
create type attendance_status as enum ('presente', 'ritardo', 'assente');
create type event_type as enum ('torneo', 'amichevole', 'allenamento', 'riunione', 'altro');
create type match_kind as enum ('torneo', 'amichevole');
create type media_type as enum ('link', 'video', 'photo');

-- ---------------------------------------------------------------- profili
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default 'Nuovo giocatore',
  gamertag text,
  avatar_url text,
  club_role club_role not null default 'pending',
  field_position text,               -- es. ATT, CC, DC, POR
  shirt_number smallint,
  joined_at date not null default current_date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Crea automaticamente il profilo (in attesa) al primo login social.
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name',
             split_part(new.email, '@', 1), 'Nuovo giocatore'),
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users for each row execute function handle_new_user();

-- Helper per le policy
create function is_direttivo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and club_role = 'direttivo');
$$;

create function is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and club_role <> 'pending' and active);
$$;

-- ---------------------------------------------------------------- formazione
create table formations (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Formazione titolare',
  module text not null default '4-3-3',
  is_current boolean not null default false,
  updated_by uuid references profiles,
  updated_at timestamptz not null default now()
);

create table formation_slots (
  formation_id uuid references formations on delete cascade,
  slot_index smallint check (slot_index between 0 and 10),
  x real not null,                    -- 0..1 posizione orizzontale sul campo
  y real not null,                    -- 0..1 posizione verticale sul campo
  label text not null,                -- es. POR, DC, CC
  player_id uuid references profiles on delete set null,
  primary key (formation_id, slot_index)
);

-- ---------------------------------------------------------------- calendario e risultati
create table events (
  id uuid primary key default gen_random_uuid(),
  type event_type not null,
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  created_by uuid references profiles,
  created_at timestamptz not null default now()
);

create table matches (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references events on delete set null,
  kind match_kind not null,
  competition text,
  opponent text not null,
  home boolean not null default true,
  goals_for smallint,
  goals_against smallint,
  scorers text,
  played_at timestamptz not null,
  notes text,
  created_at timestamptz not null default now()
);

create table match_media (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references matches on delete cascade,
  type media_type not null,
  url text,                           -- per type = link
  storage_path text,                  -- per video/foto caricati
  duration_s smallint check (duration_s is null or duration_s <= 15),
  caption text,
  uploaded_by uuid references profiles,
  created_at timestamptz not null default now(),
  check ((type = 'link' and url is not null) or (type <> 'link' and storage_path is not null))
);

-- ---------------------------------------------------------------- albo d'oro
create table seasons (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,         -- es. 2025/26
  starts_on date,
  ends_on date
);

create table trophies (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references seasons on delete cascade,
  name text not null,
  competition text,
  won_on date,
  image_path text,                    -- PNG trasparente nel bucket "trophies"
  shelf smallint not null default 0,
  position smallint not null default 0,
  description text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- regolamento & storia, social
create table pages (
  slug text primary key check (slug in ('regolamento', 'storia')),
  content text not null default '',
  updated_by uuid references profiles,
  updated_at timestamptz not null default now()
);
insert into pages (slug) values ('regolamento'), ('storia');

create table club_links (
  id uuid primary key default gen_random_uuid(),
  kind text not null,                 -- instagram, whatsapp, youtube, tiktok, twitch, sito
  url text not null,
  sort_order smallint not null default 0
);

-- ---------------------------------------------------------------- presenze
create table attendance (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references profiles on delete cascade,
  date date not null,
  status attendance_status not null,
  arrival_time time not null default '21:30',
  note text,
  updated_at timestamptz not null default now(),
  unique (player_id, date)
);

-- ---------------------------------------------------------------- notizie (scritte dal job GitHub Actions)
create table news (
  id bigint generated always as identity primary key,
  source text not null,
  category text not null check (category in ('tornei', 'aggiornamenti', 'ultimate_team', 'pro_clubs')),
  title text not null,
  summary text check (char_length(summary) <= 400),
  url text not null unique,
  image_url text,
  published_at timestamptz not null default now()
);
create index news_published_idx on news (published_at desc);

-- ---------------------------------------------------------------- Row Level Security
alter table profiles enable row level security;
alter table formations enable row level security;
alter table formation_slots enable row level security;
alter table events enable row level security;
alter table matches enable row level security;
alter table match_media enable row level security;
alter table seasons enable row level security;
alter table trophies enable row level security;
alter table pages enable row level security;
alter table club_links enable row level security;
alter table attendance enable row level security;
alter table news enable row level security;

-- Profili: ognuno vede il proprio; i membri approvati vedono tutti.
create policy "profili leggibili" on profiles for select
  using (id = auth.uid() or is_member());
-- Ognuno può aggiornare il proprio profilo ma non cambiarsi il ruolo (vedi trigger sotto).
create policy "modifica proprio profilo" on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
create policy "direttivo gestisce profili" on profiles for all
  using (is_direttivo()) with check (is_direttivo());

create function prevent_self_role_change() returns trigger
language plpgsql as $$
begin
  -- auth.uid() è null dall'editor SQL / service role: serve per nominare il primo Direttivo.
  if new.club_role is distinct from old.club_role and auth.uid() is not null and not is_direttivo() then
    raise exception 'Solo il Direttivo può cambiare i ruoli';
  end if;
  return new;
end $$;
create trigger profiles_role_guard before update on profiles
  for each row execute function prevent_self_role_change();

-- Tabelle "di club": lettura per i membri, scrittura solo Direttivo.
do $$
declare t text;
begin
  foreach t in array array['formations','formation_slots','events','matches','match_media',
                           'seasons','trophies','pages','club_links'] loop
    execute format('create policy "lettura membri" on %I for select using (is_member())', t);
    execute format('create policy "scrittura direttivo" on %I for all using (is_direttivo()) with check (is_direttivo())', t);
  end loop;
end $$;

-- Notizie: lettura per i membri; scrittura solo dal job (service role, che bypassa RLS).
create policy "lettura membri" on news for select using (is_member());

-- Presenze: tutti i membri vedono tutto; ognuno gestisce le proprie; il Direttivo tutte.
create policy "lettura membri" on attendance for select using (is_member());
create policy "proprie presenze" on attendance for all
  using (player_id = auth.uid() and is_member())
  with check (player_id = auth.uid() and is_member());
create policy "direttivo presenze" on attendance for all
  using (is_direttivo()) with check (is_direttivo());

-- ---------------------------------------------------------------- Storage
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', false),
  ('trophies', 'trophies', false),
  ('match-media', 'match-media', false);

create policy "media leggibili dai membri" on storage.objects for select
  using (bucket_id in ('avatars', 'trophies', 'match-media') and is_member());
create policy "direttivo carica media" on storage.objects for all
  using (bucket_id in ('trophies', 'match-media') and is_direttivo())
  with check (bucket_id in ('trophies', 'match-media') and is_direttivo());
create policy "avatar personale" on storage.objects for all
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Realtime per l'approvazione automatica e le presenze live.
alter publication supabase_realtime add table profiles, attendance;
