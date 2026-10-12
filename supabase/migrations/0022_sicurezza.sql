-- Sicurezza (review di ottobre 2026): chiude le falle trovate nella revisione completa.
--  1) Un membro del Direttivo rimosso (active = false) perde subito tutti i poteri.
--  2) Gli allegati della chat (foto, vocali, replay) li scarica solo chi vede il canale.
--  3) Password del Direttivo: al massimo 5 tentativi sbagliati ogni 15 minuti per account
--     (e 50 all'ora in tutto); la nuova password si salva con bcrypt a costo 12.
--  4) Un messaggio può allegare solo file caricati da chi lo scrive (niente pulizie di file altrui).
--  5) La registrazione si completa una volta sola: dopo l'ingresso squadre e ruolo li cambia
--     solo il Direttivo.
--  6) Limiti di lunghezza su nome, gamertag, posizione e volto; i messaggi di sistema troppo
--     lunghi vengono accorciati invece di bloccare formazioni, presenze e carte.
--  7) Marcatori: il nome sulla carta vale più del cognome e del gamertag, e un nome che
--     corrisponde a due giocatori non assegna gol (niente carte blu "copiando" un nome).
--  8) Eliminazione dell'account: le foto vanno nella coda di pulizia (l'API di Storage),
--     non si cancellano più dalle tabelle di Storage via SQL.
--  9) Funzioni interne non chiamabili dalle app; il permesso temporaneo della registrazione
--     vale per un solo aggiornamento del profilo.
-- 10) Token dei telefoni: un token passa all'account che lo registra (cambio di account).
-- 11) Stanza vocale: il numero utente in Agora lo calcola il server dall'id del profilo.

-- ---------------------------------------------------------------- 1) Direttivo attivo
create or replace function public.is_direttivo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and club_role = 'direttivo' and active)
$$;

-- ---------------------------------------------------------------- 2) allegati della chat
-- Si legge un file della chat se è proprio (appena caricato, prima di inviare il messaggio)
-- oppure se un messaggio visibile all'utente lo allega (le policy di messages fanno il resto:
-- canali riservati, canali dell'altra squadra).
create index if not exists messages_image_path_idx on public.messages (image_path)
  where image_path is not null;
create index if not exists messages_audio_path_idx on public.messages (audio_path)
  where audio_path is not null;
create index if not exists messages_replay_path_idx on public.messages (replay_path)
  where replay_path is not null;

drop policy if exists "foto chat leggibili dai membri" on storage.objects;
drop policy if exists "allegati chat leggibili da chi vede il canale" on storage.objects;
create policy "allegati chat leggibili da chi vede il canale" on storage.objects for select
  using (
    bucket_id = 'chat' and is_member() and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1 from public.messages m
        where (m.image_path = objects.name or m.audio_path = objects.name
               or m.replay_path = objects.name)
          and can_see_channel(m.channel_id))));

-- ---------------------------------------------------------------- 3) password del Direttivo
create table if not exists public.direttivo_password_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  at timestamptz not null default now()
);
create index if not exists direttivo_password_attempts_user_idx
  on public.direttivo_password_attempts (user_id, at);
alter table public.direttivo_password_attempts enable row level security; -- nessuna policy: solo il server

-- Controlla la password registrando i tentativi sbagliati (che restano anche se la
-- chiamata poi fallisce, perché chi chiama non solleva errori dopo un errore di password).
create or replace function public.direttivo_password_ok(p_password text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
begin
  if (select count(*) from direttivo_password_attempts
      where user_id = uid and at > now() - interval '15 minutes') >= 5
     or (select count(*) from direttivo_password_attempts
         where at > now() - interval '1 hour') >= 50 then
    raise exception 'Troppi tentativi con la password del Direttivo: riprova tra 15 minuti';
  end if;
  if check_direttivo_password(p_password) then
    return true;
  end if;
  insert into direttivo_password_attempts (user_id) values (uid);
  delete from direttivo_password_attempts where at < now() - interval '1 day';
  return false;
end $$;
revoke all on function public.direttivo_password_ok(text) from public, anon, authenticated;

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
  update app_config set value = crypt(p_new, gen_salt('bf', 12))
  where key = 'direttivo_password_hash';
end $$;
revoke all on function public.set_direttivo_password(text, text) from public, anon;
grant execute on function public.set_direttivo_password(text, text) to authenticated;

-- ---------------------------------------------------------------- 5) registrazione una volta sola
-- Restituisce 'ok' oppure 'password_errata' (senza sollevare errori, così il tentativo
-- sbagliato resta registrato per il limite qui sopra).
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
  return 'ok';
end $$;
revoke all on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb) from public, anon;
grant execute on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb) to authenticated;

-- ---------------------------------------------------------------- 9) permesso della registrazione
-- Il flag alzato dalle funzioni di registrazione vale per un solo aggiornamento del profilo:
-- il trigger lo consuma, così nella stessa transazione non si può cambiare altro.
create or replace function public.prevent_self_role_change() returns trigger
language plpgsql as $$
begin
  if current_setting('milanac.registration', true) = '1' then
    perform set_config('milanac.registration', '', true);
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

-- ---------------------------------------------------------------- 6) limiti di lunghezza
-- "not valid": valgono per i dati nuovi senza bloccare la migrazione su quelli vecchi.
alter table public.profiles drop constraint if exists profiles_display_name_len;
alter table public.profiles add constraint profiles_display_name_len
  check (char_length(display_name) between 1 and 40) not valid;
alter table public.profiles drop constraint if exists profiles_gamertag_len;
alter table public.profiles add constraint profiles_gamertag_len
  check (gamertag is null or char_length(gamertag) <= 40) not valid;
alter table public.profiles drop constraint if exists profiles_field_position_len;
alter table public.profiles add constraint profiles_field_position_len
  check (field_position is null or char_length(field_position) <= 40) not valid;
alter table public.profiles drop constraint if exists profiles_face_size;
alter table public.profiles add constraint profiles_face_size
  check (face is null or pg_column_size(face) <= 16384) not valid;

-- Il nome iniziale (dall'account social o dall'email) sta nei limiti.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, avatar_url)
  values (
    new.id,
    left(coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'), ''),
                  nullif(btrim(new.raw_user_meta_data->>'name'), ''),
                  nullif(split_part(new.email, '@', 1), ''),
                  'Nuovo giocatore'), 40),
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end $$;

-- I messaggi di sistema (formazioni, presenze, carte speciali) non superano mai il limite
-- di 2000 caratteri della chat: si accorciano invece di far fallire l'operazione che li crea.
create or replace function public.messages_fit_body() returns trigger
language plpgsql as $$
begin
  if new.kind = 'system' and char_length(new.body) > 2000 then
    new.body := left(new.body, 1999) || '…';
  end if;
  return new;
end $$;
drop trigger if exists messages_fit_body on public.messages;
create trigger messages_fit_body before insert or update of body on public.messages
  for each row execute function public.messages_fit_body();

-- ---------------------------------------------------------------- 4) allegati propri
create or replace function public.messages_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if new.reply_to is not null and not exists (
       select 1 from messages r where r.id = new.reply_to and r.channel_id = new.channel_id) then
    raise exception 'Si può rispondere solo a un messaggio dello stesso canale';
  end if;
  -- Dall'app si allegano solo file della propria cartella (uid/...).
  if uid is not null and exists (
       select 1 from (values (new.image_path), (new.audio_path), (new.replay_path)) v(p)
       where p is not null and p not like uid::text || '/%') then
    raise exception 'Allegato non valido';
  end if;
  new.expired_at := null;
  new.expires_at := case
    when new.replay_path is not null then app_now() + interval '3 days'
    when new.image_path is not null or new.audio_path is not null then app_now() + interval '60 days'
  end;
  return new;
end $$;

-- ---------------------------------------------------------------- 7) marcatori
-- Ogni nome scritto (es. "Rossi (2)") vale per un solo giocatore: prima il nome sulla
-- carta, poi il cognome, poi il gamertag; se allo stesso livello corrispondono due
-- giocatori, quel nome non assegna gol.
create or replace function public.scorer_goals(p_scorers text, p_team text)
returns table (player_id uuid, goals int)
language sql stable security definer set search_path = public as $$
  with items as (
    select k, regexp_match(btrim(i), '^(.*?)(?:\s*[x×(]\s*(\d+)\s*\)?|\s+(\d+))?\s*$', 'i') as m
    from regexp_split_to_table(coalesce(p_scorers, ''), '[,;\n]') with ordinality as t(i, k)
    where btrim(i) <> ''
  ), parsed as (
    select k,
           lower(regexp_replace(btrim(m[1]), '\s+', ' ', 'g')) as name,
           coalesce(m[2], m[3], '1')::int as n
    from items where m is not null and btrim(m[1]) <> ''
  ), players as (
    select p.id,
           lower(regexp_replace(btrim(p.display_name), '\s+', ' ', 'g')) as card,
           lower(split_part(regexp_replace(btrim(p.display_name), '\s+', ' ', 'g'), ' ',
                 array_length(string_to_array(regexp_replace(btrim(p.display_name), '\s+', ' ', 'g'), ' '), 1))) as surname,
           lower(nullif(btrim(p.gamertag), '')) as tag
    from profiles p
    where p.active and p.club_role <> 'pending' and p_team = any(p.teams)
  ), matched as (
    select parsed.k, parsed.n, pl.id,
           case when parsed.name = pl.card then 1
                when parsed.name = pl.surname then 2
                else 3 end as prio
    from parsed join players pl
      on parsed.name in (pl.card, pl.surname, coalesce(pl.tag, '?'))
  ), best as (
    select k, min(prio) as prio from matched group by k
  ), chosen as (
    select m.k, min(m.n) as n, min(m.id::text)::uuid as id
    from matched m join best b on b.k = m.k and b.prio = m.prio
    group by m.k
    having count(distinct m.id) = 1
  )
  select id, sum(n)::int from chosen group by id
$$;

-- ---------------------------------------------------------------- 8) eliminazione dell'account
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Non autenticato';
  end if;
  insert into storage_cleanup (bucket, path)
  select 'avatars', o.name from storage.objects o
  where o.bucket_id = 'avatars' and (storage.foldername(o.name))[1] = uid::text
  on conflict do nothing;
  delete from auth.users where id = uid;
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------- 9) funzioni interne
revoke all on function public.scorer_goals(text, text) from public, anon, authenticated;
revoke all on function public.formation_goalkeeper(text) from public, anon, authenticated;
revoke all on function public.match_number(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 10) token dei telefoni
create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Non autenticato';
  end if;
  if coalesce(btrim(p_token), '') = '' or char_length(p_token) > 4096 then
    raise exception 'Token non valido';
  end if;
  insert into device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), left(p_platform, 20), now())
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end $$;
revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;

-- ---------------------------------------------------------------- 11) numero utente Agora
-- Stesso calcolo dell'app (agoraUidFor) e della funzione voice-token: hash 31 dell'id.
create or replace function public.agora_uid_for(p_user uuid) returns bigint
language plpgsql immutable as $$
declare
  h bigint := 0;
  s text := p_user::text;
  i int;
begin
  for i in 1 .. char_length(s) loop
    h := (h * 31 + ascii(substr(s, i, 1))) & 2147483647;
  end loop;
  return case when h = 0 then 1 else h end;
end $$;

create or replace function public.join_voice_room(p_room uuid, p_agora_uid bigint default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  ch uuid;
  sess uuid;
  v_uid bigint := agora_uid_for(auth.uid());
begin
  select channel_id into ch from voice_rooms where id = p_room and closed_at is null;
  if ch is null or auth.uid() is null or not can_see_channel(ch) then
    raise exception 'Stanza chiusa o non disponibile';
  end if;
  select id into sess from voice_sessions
  where room_id = p_room and user_id = auth.uid() and left_at is null;
  if sess is null then
    insert into voice_sessions (room_id, user_id, agora_uid, joined_at, heartbeat_at)
    values (p_room, auth.uid(), v_uid, app_now(), app_now()) returning id into sess;
  else
    update voice_sessions set heartbeat_at = app_now(), agora_uid = v_uid where id = sess;
  end if;
  return sess;
end $$;
