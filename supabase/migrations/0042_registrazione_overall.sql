-- Registrazione con overall e stile di gioco (novembre 2026). Il percorso d'ingresso diventa:
-- dati essenziali, foto, il proprio giocatore (nome sulla carta, squadra, ruolo, overall e
-- stile di gioco), regolamento e walkout. L'overall lo dichiara chi entra (è quello del suo
-- giocatore in Pro Clubs) solo qui, alla registrazione: da quando è nel club lo cambia soltanto
-- il Direttivo, come prima (prevent_self_role_change). Il Direttivo lo legge nell'avviso del
-- nuovo ingresso e lo corregge dalla carta se non è giusto.
--
-- complete_registration prende due parametri facoltativi in più (p_overall, p_play_style): le
-- app già installate non li mandano e per loro non cambia niente (overall 60, stile vuoto).

drop function if exists public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb, text);

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
  p_club_password text default null,
  p_overall int default null,
  p_play_style text default null
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
  -- L'overall dichiarato (quello del proprio giocatore in Pro Clubs) e lo stile di gioco:
  -- gli stessi limiti della carta.
  if p_overall is not null and p_overall not between 40 and 99 then
    raise exception 'Overall non valido (da 40 a 99)';
  end if;
  if p_play_style is not null and char_length(btrim(p_play_style)) > 24 then
    raise exception 'Stile di gioco troppo lungo (massimo 24 caratteri)';
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
    -- Senza overall dichiarato (app di prima) resta quello che c'è, o 60.
    overall = coalesce(p_overall, overall, 60),
    play_style = coalesce(nullif(btrim(coalesce(p_play_style, '')), ''), play_style),
    registration_completed_at = now()
  where id = uid;
  return 'ok';
end $$;
revoke all on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb, text, int, text) from public, anon;
grant execute on function public.complete_registration(text, text, int, text, text, text[], boolean, text, text[], text, int, text, jsonb, text, int, text) to authenticated;

-- ---------------------------------------------------------------- avviso del nuovo ingresso
-- Come nella 0025, con l'overall: l'ha scelto chi entra, il Direttivo lo controlla.
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
               || coalesce(' · overall ' || new.overall, '')
               || '. Controllate l''overall (si corregge dalla sua carta) e, se non lo conoscete, '
               || 'toglietelo dalla Rosa.', 2000),
          jsonb_build_object('type', 'new_member', 'member', new.id));
  return new;
end $$;
