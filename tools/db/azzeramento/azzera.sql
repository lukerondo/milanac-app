-- Azzeramento "si riparte da zero": tutti i membri si registrano di nuovo.
-- Vanno via gli account e tutto quello che hanno creato i membri; restano la configurazione
-- e i contenuti del club (regolamento, storia, albo d'oro, canali, contatti, impostazioni).
-- Non è una migrazione: si lancia una volta sola, a mano, con il workflow "Azzeramento"
-- (prima in prova). I file nello Storage (foto profilo, allegati della chat...) li toglie
-- svuota_storage.py con l'API di Storage: da SQL Supabase non li lascia cancellare.
--
-- Il file è fatto a blocchi:
--   -- ==== BLOCCO <nome> · obbligatorio|da decidere · file: <bucket>, ...
--   ...
--   -- ==== FINE <nome>
-- "account" è obbligatorio. Un blocco "da decidere" si toglie per intero (dalla riga BLOCCO
-- alla riga FINE comprese) se il club vuole tenere quei dati: gli altri funzionano lo stesso.
-- "file:" dice quali bucket svuota_storage.py svuota per quel blocco.
-- Rilanciarlo non fa danni: la seconda volta non trova più niente da cancellare.
--
-- Prima dei blocchi i trigger delle tabelle si spengono (la cancellazione non deve mandare
-- notifiche, scrivere messaggi automatici, assegnare carte o mettere file in coda) e alla fine
-- si riaccendono. I controlli finali annullano tutto se resta un account o se è cambiata una
-- tabella che nessun blocco doveva toccare (se capita per una scrittura arrivata nello stesso
-- istante, basta rilanciare).

begin;

set local search_path = public, extensions;
set local lock_timeout = '15s';

-- ---------------------------------------------------------------- preparazione
-- Righe di ogni tabella prima dell'azzeramento, per i controlli finali.
create temp table _azz_prima on commit drop as
  select format('%I.%I', n.nspname, c.relname) as tabella,
         (xpath('/row/n/text()', query_to_xml(
            format('select count(*) as n from %I.%I', n.nspname, c.relname),
            false, true, '')))[1]::text::bigint as righe
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition;

-- Tabelle che i blocchi possono cambiare (vuota = alla fine deve restare senza righe).
create temp table _azz_svuotate (
  tabella text primary key,
  vuota boolean not null
) on commit drop;

-- Chi si registra proprio adesso aspetta la fine (il nuovo profilo non si scrive prima).
lock table public.profiles in share row exclusive mode;

-- Trigger spenti fino alla fine. I vincoli delle chiavi esterne restano attivi: le
-- cancellazioni a cascata e i "set null" funzionano come sempre.
create temp table _azz_trigger on commit drop as
  select format('%I.%I', n.nspname, c.relname) as tabella, t.tgname as nome, t.tgenabled as stato
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not t.tgisinternal and t.tgenabled <> 'D';
do $$
declare r record;
begin
  for r in select * from _azz_trigger loop
    execute format('alter table %s disable trigger %I', r.tabella, r.nome);
  end loop;
end $$;

-- ==== BLOCCO account · obbligatorio · file: avatars, chat
-- Account e dati personali: profili, dati anagrafici, token dei telefoni, canali letti e
-- silenziati, tentativi con la password del Direttivo, accessi di Supabase Auth.
-- Contenuti dei membri: tutta la chat (anche messaggi di sistema, sondaggi e voti, replay),
-- presenze, carte speciali (e quindi i traguardi), formazioni, stanze vocali con i minuti
-- (il conto del mese riparte da zero), promemoria inviati, video proposti e mai pubblicati.
insert into _azz_svuotate values
  ('public.profiles', true), ('public.profile_private', true), ('public.device_tokens', true),
  ('public.channel_reads', true), ('public.channel_mutes', true),
  ('public.direttivo_password_attempts', true),
  ('public.messages', true), ('public.poll_votes', true), ('public.attendance', true),
  ('public.special_cards', true), ('public.formations', true), ('public.formation_slots', true),
  ('public.voice_rooms', true), ('public.voice_sessions', true), ('public.event_reminders', true),
  ('public.shared_links', false), ('public.storage_cleanup', false)
on conflict do nothing;

-- Prima i contenuti, dai figli ai genitori.
delete from public.poll_votes;
delete from public.messages;
delete from public.channel_reads;
delete from public.channel_mutes;
delete from public.voice_sessions;
delete from public.voice_rooms;
delete from public.attendance;
delete from public.special_cards;
delete from public.formation_slots;
delete from public.formations;
truncate public.event_reminders restart identity;
delete from public.shared_links where status = 'proposto';
-- File in coda dei bucket che svuota_storage.py svuota per intero.
delete from public.storage_cleanup where bucket in ('avatars', 'chat');

-- Poi gli account.
delete from public.device_tokens;
delete from public.profile_private;
truncate public.direttivo_password_attempts restart identity;

-- Nelle versioni di Supabase in cui il proprietario di un file dello Storage è legato
-- all'account (chiave esterna verso auth.users) il proprietario si svuota prima: i file non
-- si cancellano da SQL e bloccherebbero la cancellazione degli account.
do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tabella, a.attname as colonna
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f' and c.confrelid = 'auth.users'::regclass
      and c.conrelid in (select oid from pg_class
                         where relnamespace = 'storage'::regnamespace
                           and relname in ('objects', 'buckets'))
  loop
    execute format('update %s set %I = null where %I is not null', r.tabella, r.colonna, r.colonna);
  end loop;
end $$;

-- Gli account di accesso: con loro spariscono a cascata i profili e, in Supabase, identità
-- (Google, Apple), sessioni, token, fattori MFA e codici usa e getta.
delete from auth.users;
delete from public.profiles;  -- già vuota per la cascata: solo per sicurezza

-- Resti di Supabase Auth senza legame con gli account: vecchi token, accessi lasciati a metà,
-- codici e registro degli accessi (email e indirizzi IP). Solo se le tabelle ci sono.
do $$
declare t text;
begin
  foreach t in array array['auth.refresh_tokens', 'auth.flow_state', 'auth.one_time_tokens',
                           'auth.audit_log_entries'] loop
    if to_regclass(t) is null then
      continue;
    elsif has_table_privilege(t, 'delete') then
      execute format('delete from %s', t);
    else
      raise notice 'Nessun permesso per svuotare %: le sue righe restano', t;
    end if;
  end loop;
end $$;
-- ==== FINE account

-- ==== BLOCCO partite · da decidere · file: match-media
-- Risultati: tutte le partite (marcatori, cronaca) con le foto e i video caricati.
-- Togliendo il blocco lo storico resta: i marcatori sono testo, il portiere si svuota.
insert into _azz_svuotate values ('public.matches', true), ('public.match_media', true)
on conflict do nothing;
delete from public.match_media;
delete from public.matches;
-- ==== FINE partite

-- ==== BLOCCO calendario · da decidere
-- Calendario: tutti gli eventi (partite in programma, allenamenti, riunioni), anche futuri.
-- Le partite già giocate restano, senza il legame con l'evento.
insert into _azz_svuotate values ('public.events', true) on conflict do nothing;
delete from public.events;
-- ==== FINE calendario

-- ==== BLOCCO tornei · da decidere · file: tournaments
-- Tornei e classifiche, con foto e loghi. Le partite restano, senza il legame con il torneo.
insert into _azz_svuotate values ('public.tournaments', true), ('public.tournament_standings', true)
on conflict do nothing;
delete from public.tournament_standings;
delete from public.tournaments;
-- ==== FINE tornei

-- ==== BLOCCO notizie · da decidere
-- Notizie raccolte dal workflow Notizie: nessun dato dei membri, tornano alla prossima
-- raccolta (ogni 3 ore).
insert into _azz_svuotate values ('public.news', true) on conflict do nothing;
truncate public.news restart identity;
-- ==== FINE notizie

-- ==== BLOCCO link_condivisi · da decidere
-- Video di Mondo Proclub pubblicati e link musicali aggiunti dai membri. Restano i cinque
-- link musicali di partenza (migrazione 0008). I video mai pubblicati li toglie già "account".
insert into _azz_svuotate values ('public.shared_links', false) on conflict do nothing;
delete from public.shared_links
where not (category = 'musica' and url in (
  'https://www.youtube.com/results?search_query=canzoni+iconiche+FIFA+soundtrack',
  'https://www.youtube.com/results?search_query=FIFA+2000s+soundtrack',
  'https://www.youtube.com/results?search_query=FIFA+2010s+soundtrack',
  'https://www.youtube.com/results?search_query=EA+SPORTS+FC+soundtrack',
  'https://open.spotify.com/search/FIFA%20soundtrack'));
-- ==== FINE link_condivisi

-- ==== BLOCCO tattiche · da decidere · file: tactics
-- Tattiche e schemi della lavagna, con le immagini. Sulla lavagna i gettoni conservano nome
-- e id dei giocatori di prima.
insert into _azz_svuotate values ('public.tactics', true) on conflict do nothing;
delete from public.tactics;
-- ==== FINE tattiche


-- ---------------------------------------------------------------- chiusura
-- Trigger di nuovo accesi, ognuno com'era.
do $$
declare r record;
begin
  for r in select * from _azz_trigger loop
    execute format('alter table %s enable %s trigger %I', r.tabella,
                   case r.stato when 'A' then 'always' when 'R' then 'replica' else '' end, r.nome);
  end loop;
end $$;

-- Controlli: se qualcosa non torna si annulla tutto (nessuna modifica resta).
do $$
declare
  r record;
  n bigint;
begin
  if exists (select 1 from auth.users) then
    raise exception 'Azzeramento annullato: in auth.users restano account';
  end if;
  for r in select p.tabella, p.righe, s.vuota
           from _azz_prima p left join _azz_svuotate s using (tabella) loop
    execute format('select count(*) from %s', r.tabella) into n;
    if r.vuota and n > 0 then
      raise exception 'Azzeramento annullato: % ha ancora % righe', r.tabella, n;
    elsif r.vuota is null and n <> r.righe then
      raise exception 'Azzeramento annullato: % è passata da % a % righe ma nessun blocco doveva toccarla',
        r.tabella, r.righe, n;
    end if;
  end loop;
  -- Senza la password nessuno entrerebbe nel Direttivo dall'app.
  if not exists (select 1 from public.app_config where key = 'direttivo_password_hash') then
    raise exception 'Azzeramento annullato: manca la password del Direttivo in app_config';
  end if;
  if exists (select 1 from _azz_trigger a
             join pg_trigger t on t.tgrelid = a.tabella::regclass and t.tgname = a.nome
             where t.tgenabled <> a.stato) then
    raise exception 'Azzeramento annullato: un trigger non è tornato com''era';
  end if;
end $$;

commit;
