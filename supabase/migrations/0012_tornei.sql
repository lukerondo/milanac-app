-- Tornei: link al sito dell'organizzatore e classifica facoltativa compilata dal Direttivo.
create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  organizer text check (organizer is null or char_length(organizer) <= 60),
  url text check (url is null or url ~* '^https?://'),
  team text not null default 'milanac' check (team in ('milanac', 'futuro')),
  status text not null default 'in_corso' check (status in ('iscrizioni', 'in_corso', 'concluso')),
  starts_on date,
  ends_on date,
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.tournament_standings (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments on delete cascade,
  team_name text not null check (char_length(team_name) between 1 and 60),
  won smallint not null default 0 check (won >= 0),
  drawn smallint not null default 0 check (drawn >= 0),
  lost smallint not null default 0 check (lost >= 0),
  goals_for smallint not null default 0 check (goals_for >= 0),
  goals_against smallint not null default 0 check (goals_against >= 0),
  is_us boolean not null default false
);
create index if not exists tournament_standings_t_idx on public.tournament_standings (tournament_id);

do $$
declare t text;
begin
  foreach t in array array['tournaments', 'tournament_standings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "lettura membri" on public.%I', t);
    execute format('create policy "lettura membri" on public.%I for select using (is_member())', t);
    execute format('drop policy if exists "scrittura direttivo" on public.%I', t);
    execute format('create policy "scrittura direttivo" on public.%I for all using (is_direttivo()) with check (is_direttivo())', t);
  end loop;
end $$;

-- Le partite possono appartenere a un torneo.
alter table public.matches
  add column if not exists tournament_id uuid references public.tournaments on delete set null;
