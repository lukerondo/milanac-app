-- Affidabilità (review di ottobre 2026): i dati arrivano aggiornati e le correzioni non si inceppano.
--  1) Tempo reale anche per partite, foto e video delle partite, tornei, schemi e canali
--     (prima l'app non riceveva le modifiche e dopo qualche tentativo mostrava un errore fisso).
--  2) Carte nero/oro: due giocatori possono scambiarsi il reparto; un giocatore, una carta.
--  3) Carte blu automatiche: si tolgono se il risultato corretto non le giustifica più;
--     a parità di orario conta l'ordine di inserimento (giornata e serie del portiere).
--  4) Traguardi: contano solo le presenze fino a oggi, non le risposte per i giorni futuri.
--  5) Formazione salvata in un colpo solo (niente bozza senza giocatori se la rete cade a metà).
--  6) Stanza vocale: una stanza per volta, il segno di vita dice se si è ancora dentro, due
--     aperture nello stesso istante non danno errore, tetto dei 10.000 minuti gratuiti del mese.
--  7) Chat: "letto fino a" con l'ora del server (niente badge fantasma con l'orologio sballato).

-- ---------------------------------------------------------------- 1) tempo reale
do $$
declare t text;
begin
  foreach t in array array['matches', 'match_media', 'tournaments', 'tactics', 'channels'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------- 2) carte nero/oro
create or replace function public.assign_special_cards(p_match uuid, p_awards jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  m matches%rowtype;
  a jsonb;
  pid uuid;
  b int;
  rep text;
  pos text;
  reps text[] := '{}';
  kept uuid[] := '{}';
  cid uuid;
  n int := 0;
begin
  if not is_direttivo() then raise exception 'Solo il Direttivo assegna le carte speciali'; end if;
  select * into m from matches where id = p_match;
  if m.id is null then raise exception 'Partita non trovata'; end if;
  if m.goals_for is null or m.goals_against is null then
    raise exception 'Inserisci prima il risultato della partita';
  end if;
  if p_awards is null or jsonb_typeof(p_awards) <> 'array' then
    raise exception 'Elenco dei premiati non valido';
  end if;
  for a in select * from jsonb_array_elements(p_awards) loop
    pid := (a->>'player_id')::uuid;
    b := coalesce((a->>'bonus')::int, 5);
    if b not between 1 and 5 then raise exception 'Il bonus va da +1 a +5'; end if;
    select field_position into pos from profiles p
    where p.id = pid and p.active and p.club_role <> 'pending' and m.team = any(p.teams);
    if not found then raise exception 'Il giocatore non è della squadra'; end if;
    if pid = any(kept) then raise exception 'Un giocatore riceve una sola carta nero/oro'; end if;
    rep := coalesce(nullif(upper(a->>'reparto'), ''), reparto_of(pos));
    if rep is null or rep not in ('POR', 'DIF', 'CEN', 'ATT') then
      raise exception 'Reparto sconosciuto: imposta la posizione in campo del giocatore';
    end if;
    if rep = any(reps) then raise exception 'Una sola carta nero/oro per reparto (%)', rep; end if;
    reps := reps || rep;
    kept := kept || pid;
  end loop;
  -- Prima si tolgono le carte che cambiano (giocatore non più in elenco o reparto diverso):
  -- così due giocatori si scambiano il reparto senza scontrarsi sull'unica carta per reparto.
  delete from special_cards s
  where s.match_id = m.id and s.kind = 'nero_oro'
    and not exists (select 1 from unnest(kept, reps) as k(pid, rep)
                    where k.pid = s.player_id and k.rep = s.reparto);
  for a in select * from jsonb_array_elements(p_awards) loop
    pid := (a->>'player_id')::uuid;
    b := coalesce((a->>'bonus')::int, 5);
    rep := reps[array_position(kept, pid)];
    if exists (select 1 from special_cards where match_id = m.id and player_id = pid and kind = 'blu') then
      continue;  -- la blu elettrico ha la precedenza
    end if;
    select id into cid from special_cards
    where match_id = m.id and player_id = pid and kind = 'nero_oro';
    if cid is null then
      perform give_special_card(pid, 'nero_oro', rep, b, 'Carta della settimana', m.id, m.team);
      n := n + 1;
    else
      update special_cards set bonus = b, assigned_by = auth.uid() where id = cid;
    end if;
  end loop;
  perform announce_special_cards(m.id);
  if exists (select 1 from special_cards where match_id = m.id) then
    perform notify_push(jsonb_build_object('kind', 'special_cards_week', 'match', m.id));
  end if;
  return n;
end $$;
revoke all on function public.assign_special_cards(uuid, jsonb) from public, anon;
grant execute on function public.assign_special_cards(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------- 3) carte blu e giornate
-- Due partite della stessa sera hanno lo stesso orario: vale l'ordine di inserimento.
create or replace function public.match_number(p_match uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int
  from matches m join matches x on x.team = m.team and x.kind = 'torneo'
  where m.id = p_match
    and x.goals_for is not null and x.goals_against is not null
    and x.played_at >= (season_start(m.played_at)::timestamp at time zone 'Europe/Rome')
    and (x.played_at, x.created_at, x.id) <= (m.played_at, m.created_at, m.id)
$$;
revoke all on function public.match_number(uuid) from public, anon, authenticated;

-- Le carte blu automatiche seguono sempre il risultato: si danno quando la condizione vale
-- e si tolgono quando una correzione (marcatori, gol subiti, portiere) la fa cadere.
-- La serie del portiere dipende dalle partite precedenti: dopo una correzione si ricontrollano
-- anche le due partite ufficiali successive della squadra.
drop function if exists public.award_blue_cards(uuid);
create or replace function public.award_blue_cards(p_match uuid, p_cascade boolean default true)
returns int
language plpgsql security definer set search_path = public as $$
declare
  m matches%rowtype;
  r record;
  n int := 0;
  hat_tricks uuid[] := '{}';
  keeper_streak boolean := false;
  removed int;
  nxt uuid;
begin
  select * into m from matches where id = p_match;
  if m.id is null then return 0; end if;
  if m.goals_for is not null and m.goals_against is not null then
    select coalesce(array_agg(s.player_id), '{}') into hat_tricks
    from scorer_goals(m.scorers, m.team) s where s.goals >= 3;
    keeper_streak := m.kind = 'torneo' and m.goals_against = 0 and m.goalkeeper_id is not null
      and (select count(*) from (
             select x.goals_against, x.goalkeeper_id from matches x
             where x.team = m.team and x.kind = 'torneo' and x.id <> m.id
               and x.goals_for is not null and x.goals_against is not null
               and (x.played_at, x.created_at, x.id) < (m.played_at, m.created_at, m.id)
             order by x.played_at desc, x.created_at desc, x.id desc
             limit 2) prev
           where prev.goals_against = 0 and prev.goalkeeper_id = m.goalkeeper_id) = 2;
  end if;
  delete from special_cards
  where match_id = m.id and kind = 'blu'
    and ((reason like 'Tripletta contro %' and not (player_id = any(hat_tricks)))
      or (reason = 'Tre partite di fila senza subire gol'
          and not (keeper_streak and player_id = m.goalkeeper_id)));
  get diagnostics removed = row_count;
  for r in select s.player_id, p.field_position
           from scorer_goals(m.scorers, m.team) s join profiles p on p.id = s.player_id
           where s.player_id = any(hat_tricks) loop
    if give_special_card(r.player_id, 'blu', coalesce(reparto_of(r.field_position), 'ATT'), 5,
                         'Tripletta contro ' || m.opponent, m.id, m.team) is not null then
      n := n + 1;
    end if;
  end loop;
  if keeper_streak then
    if give_special_card(m.goalkeeper_id, 'blu', 'POR', 5,
                         'Tre partite di fila senza subire gol', m.id, m.team) is not null then
      n := n + 1;
    end if;
  end if;
  -- L'annuncio in Comunicazioni, se c'è, segue le carte.
  if (removed > 0 or n > 0) and exists (
       select 1 from messages
       where kind = 'system' and meta->>'type' = 'special_cards' and meta->>'match' = m.id::text) then
    perform announce_special_cards(m.id);
  end if;
  if p_cascade and m.kind = 'torneo' then
    for nxt in select x.id from matches x
               where x.team = m.team and x.kind = 'torneo' and x.id <> m.id
                 and x.goals_for is not null and x.goals_against is not null
                 and (x.played_at, x.created_at, x.id) > (m.played_at, m.created_at, m.id)
               order by x.played_at, x.created_at, x.id
               limit 2 loop
      perform award_blue_cards(nxt, false);
    end loop;
  end if;
  return n;
end $$;
revoke all on function public.award_blue_cards(uuid, boolean) from public, anon, authenticated;

-- Anche togliendo il risultato si ricontrollano le carte blu (e cadono).
create or replace function public.on_match_result() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.goals_for is not null and new.goals_against is not null
     and (tg_op = 'INSERT' or old.goals_for is null or old.goals_against is null) then
    perform notify_push(jsonb_build_object('kind', 'match_result', 'id', new.id));
  end if;
  perform award_blue_cards(new.id);
  return new;
end $$;

-- ---------------------------------------------------------------- 4) traguardi
create or replace function public.player_stats(p_player uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with att as (
    select status, date from attendance
    where player_id = p_player and date <= (app_now() at time zone 'Europe/Rome')::date
  ), months as (
    select date_trunc('month', date) as m,
           count(*) filter (where status = 'presente') as pres,
           count(*) filter (where status = 'ritardo') as late
    from att group by 1
  )
  select case when not is_member() then null else jsonb_build_object(
    'presences', (select count(*) from att where status in ('presente', 'ritardo')),
    'late', (select count(*) from att where status = 'ritardo'),
    'clean_month', exists (select 1 from months where pres >= 8 and late = 0),
    'nero_oro', (select count(*) from special_cards where player_id = p_player and kind = 'nero_oro'),
    'blu', (select count(*) from special_cards where player_id = p_player and kind = 'blu')
  ) end
$$;

-- ---------------------------------------------------------------- 5) formazione
-- Salva modulo e posti in una sola transazione: [{"slot_index", "x", "y", "label", "player_id"}].
create or replace function public.save_formation(p_id uuid, p_team text, p_module text, p_slots jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare fid uuid := p_id;
begin
  if not is_direttivo() then raise exception 'Solo il Direttivo prepara la formazione'; end if;
  if p_team is null or p_team not in ('milanac', 'futuro') then raise exception 'Squadra non valida'; end if;
  if coalesce(btrim(p_module), '') = '' or char_length(p_module) > 20 then
    raise exception 'Modulo non valido';
  end if;
  if p_slots is null or jsonb_typeof(p_slots) <> 'array' or jsonb_array_length(p_slots) > 11 then
    raise exception 'Formazione non valida';
  end if;
  if fid is null then
    insert into formations (module, team, is_current, updated_by, updated_at)
    values (p_module, p_team, true, auth.uid(), now()) returning id into fid;
  else
    update formations
    set module = p_module, team = p_team, is_current = true, updated_by = auth.uid(), updated_at = now()
    where id = fid;
    if not found then raise exception 'Formazione non trovata'; end if;
  end if;
  delete from formation_slots where formation_id = fid;
  insert into formation_slots (formation_id, slot_index, x, y, label, player_id)
  select fid, (s->>'slot_index')::smallint, (s->>'x')::real, (s->>'y')::real, s->>'label',
         nullif(s->>'player_id', '')::uuid
  from jsonb_array_elements(p_slots) s;
  return fid;
end $$;
revoke all on function public.save_formation(uuid, text, text, jsonb) from public, anon;
grant execute on function public.save_formation(uuid, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------- 6) stanza vocale
-- Minuti-partecipante del mese in corso (senza controlli: solo per le funzioni qui sotto).
create or replace function public.voice_minutes_used() returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(
    ceil(extract(epoch from (coalesce(s.left_at, app_now()) - s.joined_at)) / 60.0)), 0)::int
  from voice_sessions s
  where date_trunc('month', s.joined_at at time zone 'Europe/Rome')
        = date_trunc('month', app_now() at time zone 'Europe/Rome')
$$;
revoke all on function public.voice_minutes_used() from public, anon, authenticated;

-- Apre la stanza del canale (o entra in quella già aperta) e avvisa i membri la prima volta.
-- Se due la aprono nello stesso istante, il secondo entra in quella del primo.
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
    values (p_channel, auth.uid(), app_now())
    on conflict (channel_id) where closed_at is null do nothing
    returning id into room;
    if room is null then
      select id into room from voice_rooms where channel_id = p_channel and closed_at is null;
    else
      created := true;
    end if;
  end if;
  perform join_voice_room(room, null);
  if created then
    perform notify_push(jsonb_build_object('kind', 'voice_room', 'id', room));
  end if;
  return room;
end $$;

-- Entra nella stanza (una per volta: le altre sessioni aperte si chiudono) e restituisce
-- l'id della sessione. Finiti i 10.000 minuti gratuiti del mese non si entra più.
create or replace function public.join_voice_room(p_room uuid, p_agora_uid bigint default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  ch uuid;
  sess uuid;
  other uuid;
  v_uid bigint := agora_uid_for(auth.uid());
begin
  select channel_id into ch from voice_rooms where id = p_room and closed_at is null;
  if ch is null or auth.uid() is null or not can_see_channel(ch) then
    raise exception 'Stanza chiusa o non disponibile';
  end if;
  for other in select id from voice_sessions
               where user_id = auth.uid() and left_at is null and room_id <> p_room loop
    perform leave_voice_room(other);
  end loop;
  select id into sess from voice_sessions
  where room_id = p_room and user_id = auth.uid() and left_at is null;
  if sess is null then
    if voice_minutes_used() >= 10000 then
      raise exception 'I 10.000 minuti gratuiti del mese sono finiti: la stanza vocale riapre il primo del mese';
    end if;
    insert into voice_sessions (room_id, user_id, agora_uid, joined_at, heartbeat_at)
    values (p_room, auth.uid(), v_uid, app_now(), app_now()) returning id into sess;
  else
    update voice_sessions set heartbeat_at = app_now(), agora_uid = v_uid where id = sess;
  end if;
  return sess;
end $$;

-- Segno di vita (ogni minuto dall'app): false se la sessione è già stata chiusa
-- (per esempio dopo 3 minuti senza segnale), così l'app lo dice invece di restare muta.
drop function if exists public.voice_heartbeat(uuid, boolean);
create function public.voice_heartbeat(p_session uuid, p_muted boolean default false)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update voice_sessions set heartbeat_at = app_now(), muted = p_muted
  where id = p_session and user_id = auth.uid() and left_at is null;
  return found;
end $$;
revoke all on function public.voice_heartbeat(uuid, boolean) from public, anon;
grant execute on function public.voice_heartbeat(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------- 7) chat letta
-- Segna il canale come letto fino a [p_until] (l'ora del messaggio più recente visto,
-- che è l'ora del server), mai oltre adesso e mai all'indietro.
create or replace function public.mark_channel_read(p_channel uuid, p_until timestamptz default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not can_see_channel(p_channel) then return; end if;
  insert into channel_reads (channel_id, user_id, last_read_at)
  values (p_channel, auth.uid(), least(coalesce(p_until, now()), now()))
  on conflict (channel_id, user_id)
  do update set last_read_at = greatest(channel_reads.last_read_at, excluded.last_read_at);
end $$;
revoke all on function public.mark_channel_read(uuid, timestamptz) from public, anon;
grant execute on function public.mark_channel_read(uuid, timestamptz) to authenticated;
