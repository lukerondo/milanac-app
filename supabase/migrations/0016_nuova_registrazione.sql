-- Nuova registrazione (decisioni del Direttivo, ottobre 2026):
-- si riparte da zero con i dati del club; profilo completo (nome, cognome, anno di nascita,
-- nome sulla carta, motto, etichette del Direttivo, volto); si entra nel Direttivo con la
-- password del club; regolamento con versioni e accettazione obbligatoria.
-- Spariscono i voti ai compagni, l'Uomo partita e la Squadra della settimana.

-- ---------------------------------------------------------------- 1) via i voti
drop function if exists public.match_rating_summary(uuid);
drop function if exists public.match_mvps();
drop function if exists public.team_of_the_week(date, text);
drop table if exists public.match_ratings;

-- Statistiche per i traguardi: restano presenze, ritardi e mese senza ritardi.
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
  )
  select case when not is_member() then null else jsonb_build_object(
    'presences', (select count(*) from att where status in ('presente', 'ritardo')),
    'late', (select count(*) from att where status = 'ritardo'),
    'clean_month', exists (select 1 from months where pres >= 8 and late = 0)
  ) end
$$;

-- ---------------------------------------------------------------- 2) azzeramento
-- Restano account, notizie automatiche, link social e musicali, token dei telefoni.
truncate table public.attendance, public.formation_slots, public.formations,
  public.match_media, public.matches, public.events, public.trophies, public.seasons,
  public.tactics, public.messages, public.channel_reads, public.channel_mutes,
  public.tournament_standings, public.tournaments;

-- ---------------------------------------------------------------- 3) profilo completo
alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists birth_year smallint,
  add column if not exists motto text,
  add column if not exists direttivo_roles text[] not null default '{}',
  add column if not exists face jsonb,
  add column if not exists registration_completed_at timestamptz,
  add column if not exists rules_accepted_version int,
  add column if not exists rules_accepted_at timestamptz;

alter table public.profiles drop constraint if exists profiles_first_name_check;
alter table public.profiles add constraint profiles_first_name_check
  check (first_name is null or char_length(first_name) between 1 and 40);
alter table public.profiles drop constraint if exists profiles_last_name_check;
alter table public.profiles add constraint profiles_last_name_check
  check (last_name is null or char_length(last_name) between 1 and 40);
alter table public.profiles drop constraint if exists profiles_birth_year_check;
alter table public.profiles add constraint profiles_birth_year_check
  check (birth_year is null or birth_year between 1940 and 2030);
alter table public.profiles drop constraint if exists profiles_motto_check;
alter table public.profiles add constraint profiles_motto_check
  check (motto is null or char_length(motto) <= 80);
alter table public.profiles drop constraint if exists profiles_direttivo_roles_check;
alter table public.profiles add constraint profiles_direttivo_roles_check
  check (direttivo_roles <@ array['capitano', 'reclutatore', 'organizzatore', 'gestore']);

-- Tutti ripassano dalla registrazione: il ruolo lo riprendono completandola.
update public.profiles set
  club_role = 'pending', requested_role = 'giocatore', active = true,
  overall = null, direttivo_roles = '{}', face = null,
  registration_completed_at = null, rules_accepted_version = null, rules_accepted_at = null;

-- Il membro non può cambiarsi da solo ruolo, squadre, stato, overall, etichette e accettazioni:
-- li impostano il Direttivo o le funzioni di registrazione (che alzano il flag di sessione).
create or replace function public.prevent_self_role_change() returns trigger
language plpgsql as $$
begin
  if current_setting('milanac.registration', true) = '1' then
    return new;
  end if;
  -- auth.uid() è null dall'editor SQL / service role.
  if auth.uid() is not null and not is_direttivo() and (
       new.club_role is distinct from old.club_role
    or new.requested_role is distinct from old.requested_role
    or new.teams is distinct from old.teams
    or new.active is distinct from old.active
    or new.joined_at is distinct from old.joined_at
    or new.overall is distinct from old.overall
    or new.direttivo_roles is distinct from old.direttivo_roles
    or new.registration_completed_at is distinct from old.registration_completed_at
    or new.rules_accepted_version is distinct from old.rules_accepted_version
    or new.rules_accepted_at is distinct from old.rules_accepted_at) then
    raise exception 'Solo il Direttivo può cambiare ruolo, squadra, stato, overall o data d''ingresso';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------- 4) password del Direttivo
-- Solo l'hash (bcrypt) sta nel database, in una tabella che le app non leggono.
-- Si cambia dall'app con set_direttivo_password.
create extension if not exists pgcrypto with schema extensions;

insert into public.app_config (key, value)
values ('direttivo_password_hash', '$2a$10$2zsiOtMyhD.OYVJpX6DLEeAj7JeBfxwo90pUB1Z8boRW.z7GrXu.2')
on conflict (key) do nothing;

create or replace function public.check_direttivo_password(p_password text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select p_password is not null and exists (
    select 1 from app_config
    where key = 'direttivo_password_hash' and crypt(p_password, value) = value)
$$;
revoke all on function public.check_direttivo_password(text) from public, anon, authenticated;

create or replace function public.set_direttivo_password(p_current text, p_new text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo può cambiare la password';
  end if;
  if not check_direttivo_password(p_current) then
    raise exception 'Password attuale non corretta';
  end if;
  if p_new is null or char_length(p_new) < 8 then
    raise exception 'La nuova password deve avere almeno 8 caratteri';
  end if;
  update app_config set value = crypt(p_new, gen_salt('bf'))
  where key = 'direttivo_password_hash';
end $$;
revoke all on function public.set_direttivo_password(text, text) from public, anon;
grant execute on function public.set_direttivo_password(text, text) to authenticated;

-- ---------------------------------------------------------------- 5) registrazione
-- Salva i dati del profilo e, con la password giusta, la richiesta di entrare nel Direttivo.
-- Il ruolo vero arriva con accept_rules: si entra solo dopo aver accettato il regolamento.
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
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  v_teams text[];
begin
  if uid is null then
    raise exception 'Non autenticato';
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
  -- Milan AC prima, senza doppioni.
  v_teams := array(select distinct t from unnest(coalesce(p_teams, '{}')) t order by t desc);
  if cardinality(v_teams) = 0 or not (v_teams <@ array['milanac', 'futuro']) then
    raise exception 'Squadra non valida';
  end if;
  if p_direttivo then
    if not check_direttivo_password(p_direttivo_password) then
      raise exception 'Password del Direttivo non corretta';
    end if;
    if p_direttivo_roles is null or cardinality(p_direttivo_roles) = 0 then
      raise exception 'Scegli almeno un ruolo nel Direttivo';
    end if;
  elsif cardinality(v_teams) > 1 then
    raise exception 'Un giocatore sta in una sola squadra';
  end if;

  perform set_config('milanac.registration', '1', true);
  update profiles set
    first_name = btrim(p_first_name),
    last_name = btrim(p_last_name),
    birth_year = p_birth_year,
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
end $$;
revoke all on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb) from public, anon;
grant execute on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb) to authenticated;

-- ---------------------------------------------------------------- 6) regolamento con versioni
-- Bozza di lavoro del Direttivo: gli articoli, modificabili liberamente.
create table if not exists public.rules_articles (
  id uuid primary key default gen_random_uuid(),
  sort_order smallint not null default 0,
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 8000),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles on delete set null
);
alter table public.rules_articles enable row level security;
drop policy if exists "direttivo gestisce la bozza" on public.rules_articles;
create policy "direttivo gestisce la bozza" on public.rules_articles for all
  using (is_direttivo()) with check (is_direttivo());

-- Versioni pubblicate: una fotografia degli articoli. La legge chiunque sia autenticato,
-- anche chi deve ancora completare la registrazione (deve accettarla per entrare).
create table if not exists public.rules_versions (
  number int primary key,
  snapshot jsonb not null,
  published_at timestamptz not null default now(),
  published_by uuid references public.profiles on delete set null
);
alter table public.rules_versions enable row level security;
drop policy if exists "lettura autenticati" on public.rules_versions;
create policy "lettura autenticati" on public.rules_versions for select
  using (auth.uid() is not null);

create or replace function public.publish_rules() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo può pubblicare il regolamento';
  end if;
  if not exists (select 1 from rules_articles) then
    raise exception 'Scrivi almeno un articolo';
  end if;
  insert into rules_versions (number, snapshot, published_by)
  values (
    coalesce((select max(number) from rules_versions), 0) + 1,
    (select jsonb_agg(jsonb_build_object('title', a.title, 'body', a.body) order by a.sort_order, a.updated_at)
       from rules_articles a),
    auth.uid())
  returning number into n;
  perform notify_push(jsonb_build_object('kind', 'rules', 'version', n));
  return n;
end $$;
revoke all on function public.publish_rules() from public, anon;
grant execute on function public.publish_rules() to authenticated;

-- Accettazione: solo l'ultima versione, solo a registrazione completata.
-- Alla prima accettazione il profilo prende il ruolo richiesto ed entra nel club.
create or replace function public.accept_rules(p_version int) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  latest int := (select max(number) from rules_versions);
  done timestamptz;
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  if latest is null or p_version is distinct from latest then
    raise exception 'Versione del regolamento non aggiornata';
  end if;
  select registration_completed_at into done from profiles where id = uid;
  if done is null then
    raise exception 'Completa prima la registrazione';
  end if;
  perform set_config('milanac.registration', '1', true);
  update profiles set
    rules_accepted_version = p_version,
    rules_accepted_at = now(),
    club_role = case when club_role = 'pending' then requested_role else club_role end
  where id = uid;
end $$;
revoke all on function public.accept_rules(int) from public, anon;
grant execute on function public.accept_rules(int) to authenticated;

-- Contenuti della vecchia app: l'organigramma come primo articolo e la storia del club.
insert into public.rules_articles (sort_order, title, body) values (0, 'Organigramma',
'FONDATORI: Fabio Ruggieri, Giuseppe Ruggieri, Christian Rizzi
RESP. COMUNICAZIONI E MARKETING: Giuseppe Ruggieri
RESP. TECNICO/TATTICO: Fabio Ruggieri
RECLUTATORE: Vincenzo Lauricella
RESP. TORNEI E AMICHEVOLI: Martin Farias
RESP. SOCIAL: Christian Rizzi');

insert into public.rules_versions (number, snapshot)
select 1, jsonb_agg(jsonb_build_object('title', a.title, 'body', a.body) order by a.sort_order)
from public.rules_articles a
on conflict (number) do nothing;

update public.pages set content =
'Il MilanAc viene fondato a settembre 2025 da Fabio Ruggieri, il quale (assieme a Giuseppe e Christian) crede fortemente nel progetto di ricreare le glorie vissute dall''AC MILAN nel campo reale, anche nel campo virtuale.

La squadra si forma lentamente ma impreziosendosi sempre di più di elementi validi, in quanto i fondatori sono convinti che un gruppo solido sia la base di partenza di fondamentale importanza per ottenere i risultati che i tre si aspettano.

I colori sociali del club sono il rosso ed il nero.',
  updated_at = now()
where slug = 'storia';

-- Il regolamento non sta più nella pagina libera: vive nelle versioni.
delete from public.pages where slug = 'regolamento';
alter table public.pages drop constraint if exists pages_slug_check;
alter table public.pages add constraint pages_slug_check check (slug in ('storia'));

-- Chi deve ancora entrare legge la storia insieme al regolamento.
drop policy if exists "lettura membri" on public.pages;
create policy "lettura membri" on public.pages for select using (auth.uid() is not null);
