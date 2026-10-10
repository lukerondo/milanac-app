-- Fase 3 (ottobre 2026): chat in stile Telegram e carte speciali.
-- Chat: risposta a un messaggio, messaggi vocali (max 2 minuti), foto e vocali scadono dopo
-- 60 giorni (il messaggio resta con "Allegato scaduto"); pulizia notturna con pg_cron e
-- rimozione dei file dallo Storage tramite la funzione "notify".
-- Carte speciali: la carta nero/oro della settimana (+1…+5, una per reparto, assegnata dal
-- Direttivo dal risultato) e la carta blu elettrico (automatica: tripletta, o portiere con tre
-- partite ufficiali di fila senza subire gol). Durano 7 giorni e sostituiscono la carta normale.
-- Partite: il portiere della partita (preso dalla formazione pubblicata, correggibile).

-- ---------------------------------------------------------------- 1) chat: risposte, vocali, scadenza
alter table public.messages
  add column if not exists reply_to uuid references public.messages on delete set null,
  add column if not exists audio_path text,
  add column if not exists duration_s smallint,
  add column if not exists expires_at timestamptz,   -- quando l'allegato (foto o vocale) scade
  add column if not exists expired_at timestamptz;   -- quando è stato tolto

alter table public.messages drop constraint if exists messages_duration_s_check;
alter table public.messages add constraint messages_duration_s_check
  check (duration_s is null or duration_s between 1 and 120);
alter table public.messages drop constraint if exists messages_audio_duration_check;
alter table public.messages add constraint messages_audio_duration_check
  check (audio_path is null or duration_s is not null);
-- Un messaggio ha un testo, una foto o un vocale (o aveva un allegato, poi scaduto).
alter table public.messages drop constraint if exists messages_check;
alter table public.messages add constraint messages_check
  check (coalesce(btrim(body), '') <> '' or image_path is not null or audio_path is not null
         or expired_at is not null);
create index if not exists messages_expires_idx on public.messages (expires_at)
  where expires_at is not null and expired_at is null;

-- Vocali nel bucket della chat (stessa cartella personale delle foto).
update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp',
                               'audio/mp4', 'audio/aac', 'audio/x-m4a', 'audio/m4a',
                               'audio/mpeg', 'audio/ogg', 'audio/webm', 'audio/wav']
where id = 'chat';

-- Si risponde solo a un messaggio dello stesso canale; gli allegati scadono dopo 60 giorni.
create or replace function public.messages_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.reply_to is not null and not exists (
       select 1 from messages r where r.id = new.reply_to and r.channel_id = new.channel_id) then
    raise exception 'Si può rispondere solo a un messaggio dello stesso canale';
  end if;
  new.expired_at := null;
  new.expires_at := case when new.image_path is not null or new.audio_path is not null
                         then app_now() + interval '60 days' end;
  return new;
end $$;
drop trigger if exists messages_before_insert on public.messages;
create trigger messages_before_insert before insert on public.messages
  for each row execute function public.messages_before_insert();

-- File da togliere dallo Storage: li elimina la funzione "notify" (evento "cleanup"),
-- che ha la chiave di servizio; le righe restano finché il file non è stato rimosso.
create table if not exists public.storage_cleanup (
  bucket text not null,
  path text not null,
  queued_at timestamptz not null default now(),
  primary key (bucket, path)
);
alter table public.storage_cleanup enable row level security;  -- nessuna policy: solo il server

-- Messaggio eliminato → i suoi file vanno in coda.
create or replace function public.messages_after_delete() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into storage_cleanup (bucket, path)
  select 'chat', p from (values (old.image_path), (old.audio_path)) v(p) where p is not null
  on conflict do nothing;
  return old;
end $$;
drop trigger if exists messages_after_delete on public.messages;
create trigger messages_after_delete after delete on public.messages
  for each row execute function public.messages_after_delete();

-- Ogni notte: gli allegati scaduti si tolgono dai messaggi e i file finiscono in coda.
create or replace function public.expire_attachments() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into storage_cleanup (bucket, path)
  select 'chat', p
  from messages m cross join lateral (values (m.image_path), (m.audio_path)) v(p)
  where m.expires_at <= app_now() and m.expired_at is null and p is not null
  on conflict do nothing;
  update messages set expired_at = app_now(), image_path = null, audio_path = null
  where expires_at <= app_now() and expired_at is null;
  get diagnostics n = row_count;
  if exists (select 1 from storage_cleanup) then
    perform notify_push(jsonb_build_object('kind', 'cleanup'));
  end if;
  return n;
end $$;
revoke all on function public.expire_attachments() from public, anon, authenticated;

do $$ begin
  perform cron.schedule('allegati-scaduti', '15 3 * * *', 'select public.expire_attachments()');
end $$;

-- Riepilogo dei canali: anche "ultimo messaggio vocale".
drop function if exists public.chat_overview();
create or replace function public.chat_overview()
returns table (channel_id uuid, unread int, last_body text, last_author text, last_kind text,
               last_has_image boolean, last_has_audio boolean, last_at timestamptz)
language sql stable set search_path = public as $$
  select c.id,
         (select count(*) from (
            select 1 from messages m
            where m.channel_id = c.id
              and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz)
              and m.author_id is distinct from auth.uid()
            limit 99) u)::int,
         lm.body, lm.author, lm.kind, lm.image_path is not null, lm.audio_path is not null, lm.created_at
  from channels c
  left join channel_reads r on r.channel_id = c.id and r.user_id = auth.uid()
  left join lateral (
    select m.body, m.kind, m.image_path, m.audio_path, m.created_at, p.display_name as author
    from messages m left join profiles p on p.id = m.author_id
    where m.channel_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  order by c.sort_order
$$;
revoke all on function public.chat_overview() from public, anon;
grant execute on function public.chat_overview() to authenticated;

-- ---------------------------------------------------------------- 2) partite: il portiere
alter table public.matches
  add column if not exists goalkeeper_id uuid references public.profiles on delete set null;

-- Nomi delle squadre e risultato "Milan AC 3–1 Rivali".
create or replace function public.team_name(p_team text) returns text
language sql immutable as $$
  select case p_team when 'futuro' then 'Milan AC Futuro' else 'Milan AC' end
$$;
create or replace function public.match_score(m public.matches) returns text
language sql stable as $$
  select case when m.home
    then team_name(m.team) || ' ' || m.goals_for || '–' || m.goals_against || ' ' || m.opponent
    else m.opponent || ' ' || m.goals_against || '–' || m.goals_for || ' ' || team_name(m.team) end
$$;

-- Il portiere dell'ultima formazione pubblicata della squadra.
create or replace function public.formation_goalkeeper(p_team text) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce((f.published_players->>s.slot_index::text)::uuid, s.player_id)
  from formations f join formation_slots s on s.formation_id = f.id
  where f.team = p_team and f.published_at is not null and s.label = 'POR'
  order by f.published_at desc
  limit 1
$$;

-- Quando si inserisce il risultato, il portiere viene dalla formazione (poi si può correggere).
create or replace function public.matches_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.goalkeeper_id is null and new.goals_for is not null and new.goals_against is not null
     and (tg_op = 'INSERT' or old.goals_for is null or old.goals_against is null) then
    new.goalkeeper_id := formation_goalkeeper(new.team);
  end if;
  return new;
end $$;
drop trigger if exists matches_before_write on public.matches;
create trigger matches_before_write before insert or update on public.matches
  for each row execute function public.matches_before_write();

-- ---------------------------------------------------------------- 3) carte speciali
create table if not exists public.special_cards (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles on delete cascade,
  kind text not null check (kind in ('nero_oro', 'blu')),
  reparto text not null check (reparto in ('POR', 'DIF', 'CEN', 'ATT')),
  bonus smallint not null default 5 check (bonus between 1 and 5),
  reason text check (reason is null or char_length(reason) <= 120),
  match_id uuid references public.matches on delete set null,
  team text check (team is null or team in ('milanac', 'futuro')),
  starts_at timestamptz not null default app_now(),
  ends_at timestamptz not null default app_now() + interval '7 days',
  assigned_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
-- Per partita: una carta per giocatore e tipo; una nero/oro per reparto.
create unique index if not exists special_cards_match_player_kind_idx
  on public.special_cards (match_id, player_id, kind) where match_id is not null;
create unique index if not exists special_cards_match_reparto_idx
  on public.special_cards (match_id, reparto) where match_id is not null and kind = 'nero_oro';
create index if not exists special_cards_player_idx on public.special_cards (player_id, ends_at desc);

alter table public.special_cards enable row level security;
drop policy if exists "lettura membri" on public.special_cards;
create policy "lettura membri" on public.special_cards for select using (is_member());
drop policy if exists "scrittura direttivo" on public.special_cards;
create policy "scrittura direttivo" on public.special_cards for all
  using (is_direttivo()) with check (is_direttivo());

-- Reparto di una posizione in campo (come nell'app).
create or replace function public.reparto_of(p_position text) returns text
language sql immutable as $$
  select case upper(coalesce(p_position, ''))
    when 'POR' then 'POR'
    when 'DC' then 'DIF' when 'TD' then 'DIF' when 'TS' then 'DIF'
    when 'CDC' then 'CEN' when 'CC' then 'CEN' when 'COC' then 'CEN'
    when 'ED' then 'ATT' when 'ES' then 'ATT' when 'AD' then 'ATT' when 'AS' then 'ATT'
    when 'ATT' then 'ATT'
  end
$$;

-- Inizio della stagione (1° agosto) e numero della giornata (partite ufficiali con risultato).
create or replace function public.season_start(p_at timestamptz) returns date
language sql stable as $$
  select case when extract(month from (p_at at time zone 'Europe/Rome')) >= 8
    then make_date(extract(year from (p_at at time zone 'Europe/Rome'))::int, 8, 1)
    else make_date(extract(year from (p_at at time zone 'Europe/Rome'))::int - 1, 8, 1) end
$$;
create or replace function public.match_number(p_match uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int
  from matches m join matches x on x.team = m.team and x.kind = 'torneo'
  where m.id = p_match
    and x.goals_for is not null and x.goals_against is not null
    and x.played_at >= (season_start(m.played_at)::timestamp at time zone 'Europe/Rome')
    and (x.played_at < m.played_at or (x.played_at = m.played_at and x.id <= m.id))
$$;

-- Gol per giocatore letti dai marcatori scritti a mano ("Rossi (2), Bianchi", "Neri x2"):
-- si riconoscono nome sulla carta, cognome (ultima parola) o gamertag, come nell'app.
create or replace function public.scorer_goals(p_scorers text, p_team text)
returns table (player_id uuid, goals int)
language sql stable security definer set search_path = public as $$
  with items as (
    select regexp_match(btrim(i), '^(.*?)(?:\s*[x×(]\s*(\d+)\s*\)?|\s+(\d+))?\s*$', 'i') as m
    from regexp_split_to_table(coalesce(p_scorers, ''), '[,;\n]') i
    where btrim(i) <> ''
  ), parsed as (
    select lower(regexp_replace(btrim(m[1]), '\s+', ' ', 'g')) as name,
           coalesce(m[2], m[3], '1')::int as n
    from items where m is not null and btrim(m[1]) <> ''
  )
  select p.id, sum(parsed.n)::int
  from parsed join profiles p
    on p.active and p.club_role <> 'pending' and p_team = any(p.teams)
   and parsed.name in (
     lower(regexp_replace(btrim(p.display_name), '\s+', ' ', 'g')),
     lower(split_part(regexp_replace(btrim(p.display_name), '\s+', ' ', 'g'), ' ',
           array_length(string_to_array(regexp_replace(btrim(p.display_name), '\s+', ' ', 'g'), ' '), 1))),
     lower(coalesce(nullif(btrim(p.gamertag), ''), '?'))
   )
  group by p.id
$$;

-- Una carta speciale a un giocatore (se non ce l'ha già per quella partita) con l'avviso.
create or replace function public.give_special_card(
  p_player uuid, p_kind text, p_reparto text, p_bonus int, p_reason text, p_match uuid, p_team text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  insert into special_cards (player_id, kind, reparto, bonus, reason, match_id, team, assigned_by,
                             starts_at, ends_at)
  values (p_player, p_kind, p_reparto, p_bonus, p_reason, p_match, p_team, auth.uid(),
          app_now(), app_now() + interval '7 days')
  on conflict (match_id, player_id, kind) where match_id is not null do nothing
  returning id into cid;
  if cid is not null then
    perform notify_push(jsonb_build_object('kind', 'special_card', 'id', cid));
  end if;
  return cid;
end $$;
revoke all on function public.give_special_card(uuid, text, text, int, text, uuid, text)
  from public, anon, authenticated;

-- Carte blu elettrico automatiche dal risultato: tripletta, o terza partita ufficiale di fila
-- senza subire gol per il portiere.
create or replace function public.award_blue_cards(p_match uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  m matches%rowtype;
  r record;
  n int := 0;
begin
  select * into m from matches where id = p_match;
  if m.id is null or m.goals_for is null or m.goals_against is null then return 0; end if;
  for r in select s.player_id, s.goals, p.field_position
           from scorer_goals(m.scorers, m.team) s join profiles p on p.id = s.player_id
           where s.goals >= 3 loop
    if give_special_card(r.player_id, 'blu', coalesce(reparto_of(r.field_position), 'ATT'), 5,
                         'Tripletta contro ' || m.opponent, m.id, m.team) is not null then
      n := n + 1;
    end if;
  end loop;
  if m.kind = 'torneo' and m.goals_against = 0 and m.goalkeeper_id is not null
     and (select count(*) from (
            select x.goals_against, x.goalkeeper_id from matches x
            where x.team = m.team and x.kind = 'torneo' and x.id <> m.id
              and x.goals_for is not null and x.goals_against is not null
              and (x.played_at < m.played_at or (x.played_at = m.played_at and x.id < m.id))
            order by x.played_at desc, x.id desc
            limit 2) prev
          where prev.goals_against = 0 and prev.goalkeeper_id = m.goalkeeper_id) = 2 then
    if give_special_card(m.goalkeeper_id, 'blu', 'POR', 5,
                         'Tre partite di fila senza subire gol', m.id, m.team) is not null then
      n := n + 1;
    end if;
  end if;
  return n;
end $$;
revoke all on function public.award_blue_cards(uuid) from public, anon, authenticated;

-- Risultato inserito → notifica alla squadra; a ogni modifica si controllano le carte blu.
create or replace function public.on_match_result() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.goals_for is null or new.goals_against is null then return new; end if;
  if tg_op = 'INSERT' or old.goals_for is null or old.goals_against is null then
    perform notify_push(jsonb_build_object('kind', 'match_result', 'id', new.id));
  end if;
  perform award_blue_cards(new.id);
  return new;
end $$;
drop trigger if exists match_result on public.matches;
create trigger match_result
  after insert or update of goals_for, goals_against, scorers, goalkeeper_id on public.matches
  for each row execute function public.on_match_result();

-- Il messaggio in Comunicazioni con le carte della partita (uno per partita, aggiornato).
create or replace function public.announce_special_cards(p_match uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  m matches%rowtype;
  ch uuid := (select id from channels where slug = 'comunicazioni');
  nero text;
  blu text;
  testo text;
  mid uuid;
begin
  select * into m from matches where id = p_match;
  if m.id is null or ch is null then return; end if;
  select string_agg(sc.reparto || ' ' || p.display_name || ' +' || sc.bonus, ', '
                    order by array_position(array['POR', 'DIF', 'CEN', 'ATT'], sc.reparto))
    into nero
  from special_cards sc join profiles p on p.id = sc.player_id
  where sc.match_id = m.id and sc.kind = 'nero_oro';
  select string_agg(p.display_name
                    || coalesce(' (' || lower(left(sc.reason, 1)) || substr(sc.reason, 2) || ')', ''),
                    ', ' order by p.display_name)
    into blu
  from special_cards sc join profiles p on p.id = sc.player_id
  where sc.match_id = m.id and sc.kind = 'blu';
  select id into mid from messages
  where kind = 'system' and meta->>'type' = 'special_cards' and meta->>'match' = m.id::text;
  if nero is null and blu is null then
    delete from messages where id = mid;
    return;
  end if;
  testo := 'Carte speciali '
    || case when m.kind = 'torneo' then 'della ' || match_number(m.id) || 'ª giornata'
            else 'dell''amichevole' end
    || ' (' || match_score(m) || '): ' || coalesce(nero, 'nessuna carta nero/oro')
    || case when blu is null then '' else '. Blu elettrico: ' || blu end || '.';
  if mid is null then
    insert into messages (channel_id, author_id, kind, body, meta)
    values (ch, auth.uid(), 'system', testo,
            jsonb_build_object('type', 'special_cards', 'match', m.id, 'team', m.team));
  else
    update messages set body = testo where id = mid;
  end if;
end $$;
revoke all on function public.announce_special_cards(uuid) from public, anon, authenticated;

-- Il Direttivo assegna le carte nero/oro di una partita: [{"player_id": …, "bonus": 1…5}, …],
-- una per reparto (dalla posizione del giocatore). Chi ha già la blu per quella partita la tiene.
-- Le carte non più in elenco si tolgono; l'annuncio in Comunicazioni si aggiorna.
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
    rep := coalesce(nullif(upper(a->>'reparto'), ''), reparto_of(pos));
    if rep is null or rep not in ('POR', 'DIF', 'CEN', 'ATT') then
      raise exception 'Reparto sconosciuto: imposta la posizione in campo del giocatore';
    end if;
    if rep = any(reps) then raise exception 'Una sola carta nero/oro per reparto (%)', rep; end if;
    reps := reps || rep;
    kept := kept || pid;
  end loop;
  delete from special_cards
  where match_id = m.id and kind = 'nero_oro' and not (player_id = any(kept));
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
      update special_cards set bonus = b, reparto = rep, assigned_by = auth.uid() where id = cid;
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

-- L'annuncio delle carte in Comunicazioni ha già il suo avviso dedicato.
create or replace function public.on_message_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'system' and new.meta->>'type' in ('formation', 'special_cards') then return new; end if;
  perform notify_push(jsonb_build_object('kind', 'chat_message', 'id', new.id));
  return new;
end $$;

-- Statistiche per i traguardi: anche le carte speciali ricevute.
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
    'clean_month', exists (select 1 from months where pres >= 8 and late = 0),
    'nero_oro', (select count(*) from special_cards where player_id = p_player and kind = 'nero_oro'),
    'blu', (select count(*) from special_cards where player_id = p_player and kind = 'blu')
  ) end
$$;

-- Carte in tempo reale nell'app.
do $$ begin
  alter publication supabase_realtime add table public.special_cards;
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------- 4) tornei: foto o logo
alter table public.tournaments add column if not exists image_path text;
alter table public.tournaments drop constraint if exists tournaments_image_path_check;
alter table public.tournaments add constraint tournaments_image_path_check
  check (image_path is null or image_path like id::text || '/%');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tournaments', 'tournaments', false, 5 * 1024 * 1024,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
drop policy if exists "foto tornei leggibili dai membri" on storage.objects;
create policy "foto tornei leggibili dai membri" on storage.objects for select
  using (bucket_id = 'tournaments' and is_member());
drop policy if exists "direttivo carica foto tornei" on storage.objects;
create policy "direttivo carica foto tornei" on storage.objects for all
  using (bucket_id = 'tournaments' and is_direttivo())
  with check (bucket_id = 'tournaments' and is_direttivo());
