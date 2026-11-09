-- Password di iscrizione al club. L'app si apre anche dal sito (web app), quindi chi vuole creare
-- un account deve conoscere una password che il Direttivo dà a voce ai nuovi: senza, nessuno
-- entra. Nel database c'è solo l'hash (bcrypt), in app_config che le app non leggono; la imposta
-- e la cambia il Direttivo dall'app (set_signup_password). Finché non è impostata le iscrizioni
-- sono CHIUSE: chi è già nel club continua a entrare come sempre.
--
-- Due controlli, tutti e due sul server:
--  1) alla creazione dell'account con email: l'app chiede prima un via libera per quell'email
--     (request_signup, con la password); senza via libera l'account non nasce e non parte
--     nessuna email di conferma;
--  2) al completamento della registrazione (complete_registration): chi non ha avuto il via
--     libera (login social, account nati prima di questa regola) scrive lì la password.

-- ---------------------------------------------------------------- 1) stato e password
-- signup_mode in app_config: 'aperte' toglie il controllo (solo dall'editor SQL: prove e
-- emergenze). Senza quella riga vale la password; senza password impostata sono chiuse.
create or replace function public.signup_mode() returns text
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from app_config where key = 'signup_mode' and value = 'aperte') then 'aperte'
    when exists (select 1 from app_config where key = 'signup_password_hash') then 'password'
    else 'chiuse'
  end
$$;
revoke all on function public.signup_mode() from public, anon, authenticated;

-- Per la schermata di accesso: 'password' (campo da compilare), 'chiuse' o 'aperte'.
create or replace function public.signup_status() returns text
language sql stable security definer set search_path = public as $$
  select signup_mode()
$$;
revoke all on function public.signup_status() from public;
grant execute on function public.signup_status() to anon, authenticated;

create or replace function public.check_signup_password(p_password text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select p_password is not null and exists (
    select 1 from app_config
    where key = 'signup_password_hash' and crypt(p_password, value) = value)
$$;
revoke all on function public.check_signup_password(text) from public, anon, authenticated;

-- La imposta o la cambia il Direttivo (non serve quella di prima: chi è nel Direttivo decide).
-- Vuota = iscrizioni chiuse.
create or replace function public.set_signup_password(p_new text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_direttivo() then
    raise exception 'Solo il Direttivo può cambiare la password di iscrizione';
  end if;
  if coalesce(p_new, '') = '' then
    delete from app_config where key = 'signup_password_hash';
    return;
  end if;
  if char_length(p_new) < 8 or char_length(p_new) > 72 then
    raise exception 'La password di iscrizione deve avere da 8 a 72 caratteri';
  end if;
  insert into app_config (key, value) values ('signup_password_hash', crypt(p_new, gen_salt('bf', 12)))
  on conflict (key) do update set value = excluded.value;
  -- Password nuova: i tentativi sbagliati di prima non contano più.
  delete from signup_password_attempts;
end $$;
revoke all on function public.set_signup_password(text) from public, anon;
grant execute on function public.set_signup_password(text) to authenticated;

-- ---------------------------------------------------------------- 2) tentativi sbagliati
-- Chi prova la password senza conoscerla: 5 errori in 15 minuti dalla stessa provenienza
-- (indirizzo di rete, solo come impronta) o dallo stesso account, 40 in un'ora in tutto.
create table if not exists public.signup_password_attempts (
  id bigint generated always as identity primary key,
  origin text not null,
  at timestamptz not null default now()
);
create index if not exists signup_password_attempts_idx on public.signup_password_attempts (origin, at);
alter table public.signup_password_attempts enable row level security; -- nessuna policy: solo il server

-- Da dove arriva la richiesta: l'account se c'è, altrimenti l'impronta dell'indirizzo di rete.
create or replace function public.signup_origin() returns text
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  headers json;
  ip text;
begin
  if auth.uid() is not null then
    return 'u:' || auth.uid()::text;
  end if;
  begin
    headers := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    headers := null;
  end;
  ip := btrim(split_part(coalesce(headers->>'cf-connecting-ip', headers->>'x-forwarded-for', ''), ',', 1));
  return 'i:' || encode(digest(coalesce(nullif(ip, ''), 'sconosciuto'), 'sha256'), 'hex');
end $$;
revoke all on function public.signup_origin() from public, anon, authenticated;

-- Controlla la password contando gli errori (che restano anche se chi chiama poi risponde
-- senza sollevare errori, come per la password del Direttivo).
create or replace function public.signup_password_ok(p_password text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_origin text := signup_origin();
begin
  if (select count(*) from signup_password_attempts
      where origin = v_origin and at > now() - interval '15 minutes') >= 5
     or (select count(*) from signup_password_attempts
         where at > now() - interval '1 hour') >= 40 then
    raise exception 'Troppi tentativi con la password del club: riprova tra 15 minuti';
  end if;
  if check_signup_password(p_password) then
    return true;
  end if;
  insert into signup_password_attempts (origin) values (v_origin);
  delete from signup_password_attempts where at < now() - interval '1 day';
  return false;
end $$;
revoke all on function public.signup_password_ok(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3) via libera per un'email
-- Chi ha scritto la password giusta ha 30 minuti per creare l'account con quell'email.
-- Si salva solo l'impronta dell'email: di chi non si iscrive non resta l'indirizzo.
create table if not exists public.signup_approvals (
  email_hash text primary key,
  expires_at timestamptz not null
);
alter table public.signup_approvals enable row level security; -- nessuna policy: solo il server

-- Chi ha già dato la password (alla creazione dell'account o in registrazione).
create table if not exists public.signup_passes (
  user_id uuid primary key references auth.users on delete cascade,
  at timestamptz not null default now()
);
alter table public.signup_passes enable row level security; -- nessuna policy: solo il server

-- Chi ha già completato la registrazione (o è già nel club) prima di questa regola è a posto.
insert into public.signup_passes (user_id)
select id from public.profiles
where registration_completed_at is not null or club_role <> 'pending'
on conflict do nothing;

create or replace function public.signup_email_hash(p_email text) returns text
language sql immutable set search_path = public, extensions as $$
  select encode(digest(lower(btrim(coalesce(p_email, ''))), 'sha256'), 'hex')
$$;
revoke all on function public.signup_email_hash(text) from public, anon, authenticated;

-- Prima di creare l'account: 'ok' (via libera), 'password_errata' o 'chiuse'.
create or replace function public.request_signup(p_email text, p_club_password text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_mode text := signup_mode();
begin
  if v_mode = 'aperte' then
    return 'ok';
  end if;
  if v_mode = 'chiuse' then
    return 'chiuse';
  end if;
  if coalesce(btrim(p_email), '') = '' or char_length(p_email) > 320 or position('@' in p_email) = 0 then
    raise exception 'Indirizzo email non valido';
  end if;
  if not signup_password_ok(p_club_password) then
    return 'password_errata';
  end if;
  delete from signup_approvals where expires_at < now();
  insert into signup_approvals (email_hash, expires_at)
  values (signup_email_hash(p_email), now() + interval '30 minutes')
  on conflict (email_hash) do update set expires_at = excluded.expires_at;
  return 'ok';
end $$;
revoke all on function public.request_signup(text, text) from public;
grant execute on function public.request_signup(text, text) to anon, authenticated;

-- ---------------------------------------------------------------- 4) creazione dell'account
-- Account con email e password (o link via email): serve il via libera. Gli account dei
-- login social nascono comunque (la password non può viaggiare con loro) e la danno in
-- registrazione. Gli errori qui fermano la creazione: niente account, niente email.
create or replace function public.signup_gate_before_user() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if signup_mode() = 'aperte' then
    return new;
  end if;
  if coalesce(new.raw_app_meta_data->>'provider', 'email') <> 'email' then
    return new;
  end if;
  if not exists (select 1 from signup_approvals
                 where email_hash = signup_email_hash(new.email) and expires_at > now()) then
    raise exception 'Per creare un account serve la password del club';
  end if;
  return new;
end $$;
revoke all on function public.signup_gate_before_user() from public, anon, authenticated;

-- Account creato: il via libera è consumato e resta scritto che la password è stata data.
create or replace function public.signup_gate_after_user() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from signup_approvals
  where email_hash = signup_email_hash(new.email) and expires_at > now();
  if found then
    insert into signup_passes (user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;
revoke all on function public.signup_gate_after_user() from public, anon, authenticated;

drop trigger if exists signup_gate_before on auth.users;
create trigger signup_gate_before before insert on auth.users
  for each row execute function public.signup_gate_before_user();
drop trigger if exists signup_gate_after on auth.users;
create trigger signup_gate_after after insert on auth.users
  for each row execute function public.signup_gate_after_user();

-- ---------------------------------------------------------------- 5) registrazione
-- Per la pagina di registrazione: 'ok' (non serve altro), 'password' (va scritta la password
-- del club) o 'chiuse'. Chi è già nel club non ripassa di qui.
create or replace function public.my_signup_gate() returns text
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_mode text := signup_mode();
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  if v_mode = 'aperte'
     or exists (select 1 from signup_passes where user_id = uid)
     or exists (select 1 from profiles
                where id = uid and club_role <> 'pending' and registration_completed_at is not null) then
    return 'ok';
  end if;
  return v_mode;
end $$;
revoke all on function public.my_signup_gate() from public, anon;
grant execute on function public.my_signup_gate() to authenticated;

-- Come nella 0025, con la password del club per chi non l'ha ancora data. Risposte: 'ok',
-- 'password_errata' (Direttivo), 'password_club_errata' o 'iscrizioni_chiuse'. Le app di
-- prima non mandano p_club_password: per loro un messaggio che dice di aggiornare.
drop function if exists public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb);
create function public.complete_registration(
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
  p_face jsonb,
  p_club_password text default null
) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  v_teams text[];
  v_role club_role;
  v_done timestamptz;
  v_mode text := signup_mode();
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
  if p_direttivo and (p_direttivo_roles is null or cardinality(p_direttivo_roles) = 0) then
    raise exception 'Scegli almeno un ruolo nel Direttivo';
  end if;
  if not p_direttivo and cardinality(v_teams) > 1 then
    raise exception 'Un giocatore sta in una sola squadra';
  end if;

  -- La password del club, per chi non l'ha data creando l'account. Il primo Direttivo
  -- nominato dall'editor SQL (ruolo già assegnato) non ne ha bisogno.
  if v_mode <> 'aperte' and v_role = 'pending'
     and not exists (select 1 from signup_passes where user_id = uid) then
    if v_mode = 'chiuse' then
      return 'iscrizioni_chiuse';
    end if;
    if p_club_password is null then
      raise exception 'Per registrarti serve la password del club: aggiorna l''app e riprova';
    end if;
    if not signup_password_ok(p_club_password) then
      return 'password_club_errata';
    end if;
  end if;
  -- Da qui la password del club è data (o non serviva): resta scritto, così non si richiede.
  insert into signup_passes (user_id) values (uid) on conflict do nothing;

  if p_direttivo and not direttivo_password_ok(p_direttivo_password) then
    return 'password_errata';
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
revoke all on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb, text) from public, anon;
grant execute on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------- 6) ingresso nel club
-- Il ruolo arriva accettando il regolamento (accept_rules, enter_club): chi esce da solo
-- dall'attesa deve aver dato la password del club. Con le funzioni qui sopra è sempre così:
-- questo controllo resta come seconda chiusura. Le nomine fatte dal Direttivo o dall'editor
-- SQL non passano di qui.
create or replace function public.signup_gate_enter() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.club_role = 'pending' and new.club_role <> 'pending'
     and auth.uid() = new.id
     and signup_mode() <> 'aperte'
     and not exists (select 1 from signup_passes where user_id = new.id) then
    raise exception 'Per entrare nel club serve la password di iscrizione: chiedila al Direttivo';
  end if;
  return new;
end $$;
revoke all on function public.signup_gate_enter() from public, anon, authenticated;
drop trigger if exists signup_gate_enter on public.profiles;
create trigger signup_gate_enter before update of club_role on public.profiles
  for each row execute function public.signup_gate_enter();
