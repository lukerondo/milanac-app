#!/usr/bin/env bash
# Prova in locale dell'azzeramento, senza mai collegarsi a Supabase.
# Come tools/db/test/run.sh crea un database con tutte le migrazioni e i dati di checks.sql,
# aggiunge le parti di Supabase che lì mancano (altre tabelle di auth, Storage che non lascia
# cancellare file da SQL, proprietario dei file legato all'account) e una riga in ogni tabella.
# Poi:
#  1) prova come la manda il workflow (dry run): si annulla e non cambia niente, anche
#     togliendo uno qualsiasi dei blocchi da decidere;
#  2) azzera.sql completo: account e contenuti dei membri spariscono, il resto del club resta
#     identico, nessuna notifica e nessuna riga nuova, trigger di nuovo accesi;
#  3) una seconda volta, con la nuova password del Direttivo: non cambia nient'altro;
#  4) nuova registrazione: il primo entra nel Direttivo con la password, poi un giocatore;
#     anche il primo Direttivo nominato dall'editor SQL;
#  5) svuota_storage.py contro uno Storage finto in locale.
# Uso: PGHOST=... PGUSER=... [PGPORT=... PGPASSWORD=...] tools/db/azzeramento/prova_locale.sh
set -euo pipefail
export PGOPTIONS="-c client_min_messages=error"
unset NUOVA_PASSWORD_DIRETTIVO DRY_RUN CONFERMA BUCKETS  # le imposta la prova, caso per caso
cd "$(dirname "$0")/../../.."
DIR=tools/db/azzeramento
DB="milanac_azzera_$$"
TMP="$(mktemp -d)"
psql -v ON_ERROR_STOP=1 -q -X -d postgres -c "create database $DB"
trap 'psql -q -X -d postgres -c "drop database if exists $DB with (force)" >/dev/null; rm -rf "$TMP"' EXIT

run() { psql -v ON_ERROR_STOP=1 -q -X -d "$DB" "$@"; }
val() { psql -v ON_ERROR_STOP=1 -q -X -At -d "$DB" -c "$1"; }
fail() { echo "ERRORE: $*" >&2; exit 1; }

echo "→ database di prova: migrazioni e dati di checks.sql"
run -f tools/db/test/supabase_stubs.sql
for f in supabase/migrations/*.sql; do
  sed -E -e 's/^create extension if not exists pg_net.*$/-- (pg_net: stub di test)/' \
         -e 's/^create extension if not exists pg_cron.*$/-- (pg_cron: stub di test)/' "$f" \
    | run -1 -f -
done
run -f tools/db/test/checks.sql >/dev/null

echo "→ parti di Supabase in più e una riga in ogni tabella"
run >/dev/null <<'SQL'
-- Tabelle di Supabase Auth che gli stub non hanno (ridotte, con le stesse cascate).
create table auth.identities (id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade, provider text not null);
create table auth.sessions (id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade);
create table auth.refresh_tokens (id bigserial primary key, token text, user_id varchar(255),
  session_id uuid references auth.sessions on delete cascade);
create table auth.mfa_factors (id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade);
create table auth.one_time_tokens (id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade, token_hash text);
create table auth.flow_state (id uuid primary key default gen_random_uuid(), user_id uuid, auth_code text);
create table auth.audit_log_entries (id uuid primary key default gen_random_uuid(), payload json);

-- Storage come in Supabase: niente cancellazioni da SQL; nelle versioni meno recenti il
-- proprietario del file è legato all'account (e ne blocca la cancellazione).
alter table storage.objects add constraint objects_owner_fkey foreign key (owner) references auth.users;
create function storage.protect_delete() returns trigger language plpgsql as $$
begin
  raise exception 'Direct deletion from storage tables is not allowed. Use the Storage API instead.';
end $$;
create trigger protect_objects_delete before delete on storage.objects
  for each statement execute function storage.protect_delete();

-- Password del Direttivo di prima (in chiaro solo qui).
update public.app_config set value = crypt('password-di-prima', gen_salt('bf'))
where key = 'direttivo_password_hash';

-- Un membro con una tripletta in una partita il cui portiere si è registrato prima di lui:
-- cancellando gli account con i trigger accesi, al "set null" del portiere la carta blu del
-- bomber verrebbe riassegnata (con la notifica) prima che sparisca anche lui.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000b0', 'bomber@example.com', '{"full_name": "BOMBER"}');
update public.profiles set club_role = 'giocatore', teams = array['milanac'], field_position = 'ATT'
where id = '00000000-0000-0000-0000-0000000000b0';
insert into public.matches (id, kind, opponent, played_at, team, goals_for, goals_against, scorers, goalkeeper_id)
values ('00000000-0000-0000-0000-00000000b0b0', 'torneo', 'Rivali FC', now() - interval '1 day',
        'milanac', 3, 0, 'BOMBER (3)', '00000000-0000-0000-0000-00000000000d');

-- Tabelle che checks.sql lascia vuote, e contenuti del club legati a un membro.
insert into public.seasons (id, label) values ('00000000-0000-0000-0000-00000000005e', '2025/26');
insert into public.trophies (season_id, name, image_path)
values ('00000000-0000-0000-0000-00000000005e', 'Coppa di prova', 'coppa.png');
insert into public.match_media (match_id, type, storage_path, uploaded_by)
values ('00000000-0000-0000-0000-00000000b0b0', 'photo', '00000000-0000-0000-0000-00000000b0b0/foto.jpg',
        '00000000-0000-0000-0000-00000000000d');
insert into public.direttivo_password_attempts (user_id) values ('00000000-0000-0000-0000-00000000000b');
insert into public.shared_links (category, title, url, status, created_by) values
  ('video', 'Proposta di un membro', 'https://example.com/proposta', 'proposto', '00000000-0000-0000-0000-0000000000a1'),
  ('video', 'Video pubblicato', 'https://example.com/video', 'pubblicato', '00000000-0000-0000-0000-0000000000a1'),
  ('musica', 'Playlist di un membro', 'https://example.com/playlist', 'pubblicato', '00000000-0000-0000-0000-0000000000a1');
update public.pages set updated_by = '00000000-0000-0000-0000-00000000000d';
update public.rules_articles set updated_by = '00000000-0000-0000-0000-00000000000d';
update public.events set created_by = '00000000-0000-0000-0000-00000000000d';
update public.tactics set created_by = '00000000-0000-0000-0000-00000000000d',
  board = '{"tokens": [{"p": "00000000-0000-0000-0000-0000000000a1", "n": "Rossi"}]}';

-- File in ogni bucket, con il proprietario.
insert into storage.objects (bucket_id, name, owner) values
  ('match-media', '00000000-0000-0000-0000-00000000b0b0/foto.jpg', '00000000-0000-0000-0000-00000000000d'),
  ('trophies', 'coppa.png', '00000000-0000-0000-0000-00000000000d'),
  ('chat', '00000000-0000-0000-0000-0000000000a1/foto.jpg', '00000000-0000-0000-0000-0000000000a1'),
  ('avatars', '00000000-0000-0000-0000-0000000000b0/foto_1.jpg', '00000000-0000-0000-0000-0000000000b0');
update storage.objects set owner = '00000000-0000-0000-0000-00000000000d' where owner is null;

-- Accessi di Supabase Auth.
insert into auth.identities (user_id, provider) select id, 'google' from auth.users;
insert into auth.sessions (user_id) select id from auth.users;
insert into auth.refresh_tokens (token, user_id, session_id) select 't-' || id, user_id::text, id from auth.sessions;
insert into auth.refresh_tokens (token, user_id) values ('senza-sessione', '00000000-0000-0000-0000-00000000000d');
insert into auth.mfa_factors (user_id) values ('00000000-0000-0000-0000-00000000000d');
insert into auth.one_time_tokens (user_id, token_hash) values ('00000000-0000-0000-0000-0000000000a1', 'x');
insert into auth.flow_state (user_id, auth_code) values ('00000000-0000-0000-0000-0000000000a1', 'codice');
insert into auth.audit_log_entries (payload) values ('{"action": "login", "actor_username": "g@example.com"}');

do $$
declare t text; n bigint;
begin
  for t in select format('%I.%I', schemaname, tablename) from pg_tables
           where schemaname in ('public', 'auth') loop
    execute format('select count(*) from %s', t) into n;
    if n = 0 then raise exception 'Tabella vuota prima della prova: %', t; end if;
  end loop;
end $$;

-- Fotografie del database: righe e impronta di ogni tabella (senza le colonne che puntano
-- agli account, che l'azzeramento svuota con "set null") e valori delle sequenze.
create schema prova;
create table prova.foto (momento text, oggetto text, righe bigint, impronta text, primary key (momento, oggetto));
create function prova.impronta(t regclass) returns text language plpgsql as $$
declare escludi text[]; r text;
begin
  select coalesce(array_agg(a.attname::text), '{}') into escludi
  from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
  where c.contype = 'f' and c.conrelid = t
    and c.confrelid in ('public.profiles'::regclass, 'auth.users'::regclass);
  execute format('select md5(coalesce(string_agg(j, %L order by j), %L)) '
                 'from (select (to_jsonb(riga_) - %L::text[])::text as j from %s riga_) s', '|', '', escludi, t)
    into r;
  return r;
end $$;
create function prova.scatta(p text) returns void language plpgsql as $$
declare r record;
begin
  delete from prova.foto where momento = p;
  for r in select c.oid::regclass as t, format('%I.%I', n.nspname, c.relname) as nome
           from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where c.relkind = 'r' and n.nspname in ('public', 'auth', 'storage', 'cron', 'net') loop
    execute format('insert into prova.foto select %L, %L, count(*), prova.impronta(%L) from %s',
                   p, r.nome, r.t, r.t);
  end loop;
  insert into prova.foto
  select p, format('seq:%I.%I', schemaname, sequencename), coalesce(last_value, 0), null from pg_sequences;
end $$;
create function prova.diverse(a text, b text) returns setof text language sql as $$
  select oggetto from (select * from prova.foto where momento = a) x
  full join (select * from prova.foto where momento = b) y using (oggetto)
  where x.righe is distinct from y.righe or x.impronta is distinct from y.impronta
  order by 1
$$;

-- Categoria di ogni tabella di public (la prova si ferma se ne compare una nuova).
create table prova.categorie (tabella text primary key, categoria text not null);
insert into prova.categorie values
  ('public.profiles', 'ACCOUNT'), ('public.profile_private', 'ACCOUNT'),
  ('public.device_tokens', 'ACCOUNT'), ('public.channel_reads', 'ACCOUNT'),
  ('public.channel_mutes', 'ACCOUNT'), ('public.direttivo_password_attempts', 'ACCOUNT'),
  ('public.messages', 'MEMBER_CONTENT'), ('public.poll_votes', 'MEMBER_CONTENT'),
  ('public.attendance', 'MEMBER_CONTENT'), ('public.special_cards', 'MEMBER_CONTENT'),
  ('public.formations', 'MEMBER_CONTENT'), ('public.formation_slots', 'MEMBER_CONTENT'),
  ('public.voice_rooms', 'MEMBER_CONTENT'), ('public.voice_sessions', 'MEMBER_CONTENT'),
  ('public.event_reminders', 'MEMBER_CONTENT'), ('public.storage_cleanup', 'MEMBER_CONTENT'),
  ('public.matches', 'DECIDE'), ('public.match_media', 'DECIDE'), ('public.events', 'DECIDE'),
  ('public.tournaments', 'DECIDE'), ('public.tournament_standings', 'DECIDE'),
  ('public.news', 'DECIDE'), ('public.tactics', 'DECIDE'), ('public.shared_links', 'DECIDE'),
  ('public.pages', 'CLUB_CONTENT'), ('public.club_links', 'CLUB_CONTENT'),
  ('public.seasons', 'CLUB_CONTENT'), ('public.trophies', 'CLUB_CONTENT'),
  ('public.rules_articles', 'CLUB_CONTENT'), ('public.rules_versions', 'CLUB_CONTENT'),
  ('public.channels', 'SETTINGS'), ('public.app_config', 'SETTINGS'), ('public.daily_jobs', 'SETTINGS');
do $$
declare t text;
begin
  for t in select format('public.%I', tablename) from pg_tables where schemaname = 'public'
           except select tabella from prova.categorie loop
    raise exception 'Tabella di public senza categoria nella prova: %', t;
  end loop;
end $$;
select prova.scatta('prima');
SQL

# Blocchi da decidere ancora presenti in azzera.sql (il club può averne tolti) e loro tabelle:
# quelle dei blocchi presenti si svuotano, quelle dei blocchi tolti restano.
read -r -a DECIDERE <<< "$(python3 -c "
import sys; sys.path.insert(0, '$DIR'); import blocchi
print(' '.join(b.nome for b in blocchi.leggi(blocchi.FILE_SQL.read_text(encoding='utf-8')) if not b.obbligatorio))")"
presente() { [[ " ${DECIDERE[*]} " == *" $1 "* ]]; }
declare -A TABELLE=(
  [partite]="public.matches public.match_media"
  [calendario]="public.events"
  [tornei]="public.tournaments public.tournament_standings"
  [notizie]="public.news"
  [link_condivisi]=""
  [tattiche]="public.tactics"
  [password_direttivo]=""
)
VIA=""; TENUTE=""
for b in "${!TABELLE[@]}"; do
  if presente "$b"; then VIA+=" ${TABELLE[$b]}"; else TENUTE+=" ${TABELLE[$b]}"; fi
done
link_tot=$(val "select count(*) from public.shared_links")
link_proposti=$(val "select count(*) from public.shared_links where status = 'proposto'")
if presente link_condivisi; then LINK_DOPO=5; else LINK_DOPO=$((link_tot - link_proposti)); fi
if presente password_direttivo; then PW='nuova-password-2026'; else PW=''; fi
echo "     blocchi da decidere presenti: ${DECIDERE[*]:-nessuno}"

echo "→ righe prima dell'azzeramento"
val "select string_agg(format('%s=%s', oggetto, righe), ' ' order by oggetto) from prova.foto
     where momento = 'prima' and oggetto not like 'seq:%' and oggetto not like 'prova.%'" | fold -s -w 110

# ---------------------------------------------------------------- 1) prova (dry run)
# Una prova con l'SQL che manderebbe il workflow: deve fermarsi sul rapporto e annullarsi.
prova_sql() {  # $1 = blocchi da togliere; scrive $TMP/rapporto.txt
  python3 "$DIR/esegui.py" --stampa prova --senza "$1" > "$TMP/prova.sql"
  if run -f "$TMP/prova.sql" 2> "$TMP/prova.err"; then fail "la prova (senza: $1) doveva annullarsi"; fi
  python3 "$DIR/esegui.py" --rapporto "$TMP/prova.err" > "$TMP/rapporto.txt" \
    || { cat "$TMP/prova.err" >&2; fail "prova senza [$1]: fermata da un errore vero"; }
}
cambia() { grep -q "^$1 " "$TMP/rapporto.txt"; }

echo "→ 1) prova completa (dry run${PW:+, con nuova password}): rapporto delle tabelle che cambierebbero"
NUOVA_PASSWORD_DIRETTIVO="$PW" prova_sql ""
sed 's/^/     /' "$TMP/rapporto.txt"
for t in auth.users auth.identities auth.sessions auth.refresh_tokens auth.flow_state \
         auth.audit_log_entries public.profiles public.messages public.attendance $VIA; do
  cambia "$t" || fail "la prova non svuota $t"
done
for t in public.channels public.rules_versions public.pages public.trophies public.club_links \
         storage.objects:avatars storage.objects:chat $TENUTE; do
  if cambia "$t"; then fail "la prova cambia $t"; fi
done
grep -qx "public.shared_links $link_tot -> $LINK_DOPO" "$TMP/rapporto.txt" || fail "link condivisi nella prova"

echo "→ 1b) ogni blocco da decidere si può togliere"
for b in "${DECIDERE[@]}"; do
  prova_sql "$b"
  for t in ${TABELLE[$b]:-}; do
    if cambia "$t"; then fail "senza il blocco $b, $t non doveva cambiare"; fi
  done
  if [ "$b" = link_condivisi ]; then
    grep -qx "public.shared_links $link_tot -> $((link_tot - link_proposti))" "$TMP/rapporto.txt" \
      || fail "senza link_condivisi vanno via solo le proposte dei membri"
  fi
  echo "     senza $b: ok ($(wc -l < "$TMP/rapporto.txt") tabelle cambierebbero)"
done
if [ "${#DECIDERE[@]}" -gt 0 ]; then
  prova_sql "$(IFS=,; echo "${DECIDERE[*]}")"
  for t in $VIA; do
    if cambia "$t"; then fail "con il solo blocco account, $t non doveva cambiare"; fi
  done
  grep -qx "public.shared_links $link_tot -> $((link_tot - link_proposti))" "$TMP/rapporto.txt" \
    || fail "con il solo blocco account vanno via solo le proposte dei membri"
  echo "     solo account: ok ($(wc -l < "$TMP/rapporto.txt") tabelle cambierebbero)"
fi

echo "→ 1c) esegui.py come nel workflow, in prova (Management API sostituita da psql in locale)"
PGDATABASE="$DB" DRY_RUN=1 python3 "$DIR/prova_esegui.py" > "$TMP/esegui.txt" \
  || { cat "$TMP/esegui.txt" >&2; fail "esegui.py in prova"; }
grep -E "←|^Modalità|^Blocchi|^Nuova password|Database invariato|^\* dopo" "$TMP/esegui.txt" | sed 's/^/     /'
grep -q "Database invariato" "$TMP/esegui.txt" || fail "esegui.py: la prova doveva lasciare tutto com'era"

run -c "select prova.scatta('dopo_prove')" >/dev/null
diverse=$(val "select string_agg(d, ', ') from prova.diverse('prima', 'dopo_prove') d")
[ -z "$diverse" ] || fail "le prove hanno cambiato il database: $diverse"
echo "     database identico a prima dopo tutte le prove (anche sequenze e password)"

# Controprova (solo informativa, annullata): lo stesso azzera.sql senza spegnere i trigger.
notify_prima=$(val "select count(*) from net.calls")
coda_prima=$(val "select count(*) from public.storage_cleanup")
sed -e '/disable trigger/d' \
    -e "s/^commit;\$/select 'notify=' || count(*) from net.calls; select 'coda=' || count(*) from public.storage_cleanup;\nrollback;/" \
    "$DIR/azzera.sql" > "$TMP/con_trigger.sql"
# La riga che metterebbe in coda i file dei messaggi, prima che azzera.sql svuoti la coda.
sed -i "s/^delete from public.messages;\$/delete from public.messages;\nselect 'coda_messaggi=' || count(*) from public.storage_cleanup;/" "$TMP/con_trigger.sql"
if out=$(psql -v ON_ERROR_STOP=1 -q -X -At -d "$DB" -f "$TMP/con_trigger.sql" 2>&1); then
  n=$(sed -n 's/^notify=//p' <<< "$out"); q=$(sed -n 's/^coda_messaggi=//p' <<< "$out")
  echo "     controprova con i trigger accesi: controlli superati, $((n - notify_prima)) chiamate a notify," \
       "$((q - coda_prima)) file messi in coda (poi svuotata)"
else
  echo "     controprova con i trigger accesi: $(grep -m1 ERROR <<< "$out")"
fi

# ---------------------------------------------------------------- 2) azzeramento completo
echo "→ 2) azzera.sql completo"
run -f "$DIR/azzera.sql"
# Le tabelle dei blocchi da decidere tolti devono restare (stesse righe).
run -v tenute="$TENUTE" -v link_dopo="$LINK_DOPO" -v pw="$PW" >/dev/null <<'SQL'
update prova.categorie set categoria = 'TENUTA'
where tabella = any (string_to_array(btrim(:'tenute'), ' '));
create table prova.opzioni as select :'link_dopo'::int as link_dopo, nullif(:'pw', '') as pw;
SQL
run >/dev/null <<'SQL'
select prova.scatta('dopo1');
do $$
declare r record; n bigint;
begin
  for r in select c.tabella, c.categoria, f.righe, p.righe as prima, f.impronta, p.impronta as impronta_prima
           from prova.categorie c
           join prova.foto f on f.oggetto = c.tabella and f.momento = 'dopo1'
           join prova.foto p on p.oggetto = c.tabella and p.momento = 'prima' loop
    if r.categoria in ('ACCOUNT', 'MEMBER_CONTENT', 'DECIDE') and r.tabella <> 'public.shared_links'
       and r.righe <> 0 then
      raise exception '% (%) doveva essere vuota: % righe', r.tabella, r.categoria, r.righe;
    elsif r.categoria = 'TENUTA' and r.righe <> r.prima then
      raise exception '% (blocco tolto) doveva restare: % righe invece di %', r.tabella, r.righe, r.prima;
    elsif r.categoria in ('CLUB_CONTENT', 'SETTINGS')
          and (r.righe <> r.prima or r.impronta <> r.impronta_prima) then
      raise exception '% (%) doveva restare identica', r.tabella, r.categoria;
    end if;
  end loop;
  -- Tutte le tabelle di auth sono vuote.
  for r in select oggetto, righe from prova.foto where momento = 'dopo1' and oggetto like 'auth.%' loop
    if r.righe <> 0 then raise exception '% doveva essere vuota', r.oggetto; end if;
  end loop;
  -- Link condivisi: niente proposte dei membri; con il blocco link_condivisi solo i cinque di partenza.
  assert (select count(*) from public.shared_links) = (select link_dopo from prova.opzioni)
     and not exists (select 1 from public.shared_links where status = 'proposto'),
    'link condivisi';
  -- Storage, lavori programmati e notifiche: nessuna riga in più o in meno.
  assert (select count(*) from prova.diverse('prima', 'dopo1') d
          where d in ('storage.objects', 'storage.buckets', 'cron.job', 'net.calls')) = 0,
    'storage, cron e notifiche invariati';
  assert (select count(*) from storage.objects where owner is not null) = 0, 'proprietari dei file svuotati';
  -- Trigger di nuovo accesi, sequenze ripartite, password di prima.
  assert (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'D') = 0, 'trigger accesi';
  assert (select count(*) from pg_sequences where schemaname = 'public' and last_value is not null
          and sequencename in ('event_reminders_id_seq', 'direttivo_password_attempts_id_seq', 'news_id_seq')
          and not (sequencename = 'news_id_seq' and exists (
                     select 1 from prova.categorie where tabella = 'public.news' and categoria = 'TENUTA'))) = 0,
    'sequenze ripartite da 1';
  assert check_direttivo_password('password-di-prima'), 'password del Direttivo invariata';
end $$;
SQL
val "select string_agg(format('%s %s->%s', p.oggetto, p.righe, d.righe), ', ' order by p.oggetto)
     from prova.foto p join prova.foto d on d.oggetto = p.oggetto and d.momento = 'dopo1'
     where p.momento = 'prima' and p.righe <> d.righe and p.oggetto not like 'seq:%'" \
  | sed 's/^/     svuotate: /' | fold -s -w 110
val "select string_agg(format('%s %s', oggetto, righe), ', ' order by oggetto) from prova.foto f
     where momento = 'dopo1' and righe > 0 and oggetto not like 'seq:%' and oggetto not like 'prova.%'" \
  | sed 's/^/     restano: /' | fold -s -w 110

# ---------------------------------------------------------------- 3) di nuovo
echo "→ 3) di nuovo, con esegui.py come nel workflow (azzeramento vero)${PW:+ e la nuova password del Direttivo}"
if PGDATABASE="$DB" DRY_RUN=0 python3 "$DIR/prova_esegui.py" > "$TMP/esegui.txt"; then
  fail "esegui.py senza CONFERMA=AZZERA doveva rifiutarsi"
fi
PGDATABASE="$DB" DRY_RUN=0 CONFERMA=AZZERA NUOVA_PASSWORD_DIRETTIVO="$PW" \
  python3 "$DIR/prova_esegui.py" > "$TMP/esegui.txt" || { cat "$TMP/esegui.txt" >&2; fail "esegui.py vero"; }
grep -E "←|^Modalità|^Nuova password|Azzeramento fatto" "$TMP/esegui.txt" | sed 's/^/     /'
if [ -n "$PW" ] && grep -qF "$PW" "$TMP/esegui.txt"; then fail "esegui.py ha stampato la password"; fi
run >/dev/null <<'SQL'
select prova.scatta('dopo2');
do $$
declare pw text := (select pw from prova.opzioni);
begin
  if pw is null then
    assert not exists (select 1 from prova.diverse('dopo1', 'dopo2')), 'la seconda volta non cambia niente';
    assert check_direttivo_password('password-di-prima'), 'password di prima';
  else
    assert (select array_agg(d) from prova.diverse('dopo1', 'dopo2') d) = array['public.app_config'],
      'la seconda volta cambia solo la password';
    assert check_direttivo_password(pw), 'nuova password attiva';
    assert not check_direttivo_password('password-di-prima'), 'password di prima disattivata';
  end if;
end $$;
SQL
echo "     nient'altro è cambiato"

# ---------------------------------------------------------------- 4) nuova registrazione
echo "→ 4) nuova registrazione"
run >/dev/null <<'SQL'
select set_config('milanac.now',
  ((((now() at time zone 'Europe/Rome')::date)::text || ' 17:00')::timestamp at time zone 'Europe/Rome')::text, false);
create temp table n0 as select count(*) as n from net.calls;
-- Password del Direttivo valida adesso e una che non vale.
select set_config('prova.pw', coalesce((select pw from prova.opzioni), 'password-di-prima'), false),
       set_config('prova.pw_sbagliata', case when (select pw from prova.opzioni) is null
                                             then 'password-sbagliata' else 'password-di-prima' end, false);
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000c1', 'capo@example.com', '{"full_name": "Nuovo Capo"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'giocatore@example.com', '{}');
set role authenticated;

-- Il primo: Direttivo con la password del club.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$ begin
  assert (select count(*) from profiles) = 1, 'vede solo il proprio profilo';
  assert (select club_role from profiles) = 'pending', 'in attesa';
  assert (select count(*) from rules_versions) >= 1, 'legge il regolamento';
  assert (select count(*) from pages where slug = 'storia') = 1, 'e la storia del club';
  assert (select complete_registration('Nuovo', 'Capo', 1990, 'CAPO', null, array['milanac', 'futuro'],
          true, current_setting('prova.pw_sbagliata'), array['capitano'], 'CC', 10, 'ps5', null))
         = 'password_errata', 'con la password sbagliata non si entra nel Direttivo';
  assert (select complete_registration('Nuovo', 'Capo', 1990, 'CAPO', null, array['milanac', 'futuro'],
          true, current_setting('prova.pw'), array['capitano'], 'CC', 10, 'ps5', null)) = 'ok',
    'registrazione del Direttivo';
end $$;
select accept_rules((select max(number) from rules_versions));
do $$ begin
  assert (select club_role from profiles where id = auth.uid()) = 'direttivo', 'entrato nel Direttivo';
  assert is_direttivo(), 'con i poteri del Direttivo';
  assert (select count(*) from channels) = 6, 'vede tutti i canali, Sala Direttivo compresa';
end $$;
insert into events (type, title, starts_at) values ('allenamento', 'Si riparte', now() + interval '1 day');
insert into messages (channel_id, author_id, body)
  select id, auth.uid(), 'Benvenuti!' from channels where slug = 'main';

-- Poi un giocatore.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', false);
do $$ begin
  assert (select complete_registration('Primo', 'Giocatore', 2000, 'GIOCATORE', null, array['milanac'],
          false, null, null, 'ATT', 9, 'ps5', null)) = 'ok', 'registrazione del giocatore';
end $$;
select accept_rules((select max(number) from rules_versions));
insert into attendance (player_id, date, status)
  values (auth.uid(), (app_now() at time zone 'Europe/Rome')::date, 'presente');
do $$ begin
  assert (select club_role from profiles where id = auth.uid()) = 'giocatore', 'entrato come giocatore';
  assert (select count(*) from messages where body = 'Benvenuti!') = 1, 'legge la chat';
  assert (select count(*) from events where title = 'Si riparte') = 1, 'legge il calendario';
  assert (select count(*) from channels where slug = 'direttivo') = 0, 'non vede la Sala Direttivo';
  assert (select count(*) from profiles) = 2, 'vede la nuova rosa';
end $$;
reset role;
do $$ begin
  assert (select count(*) from messages where meta->>'type' = 'new_member') = 2,
    'avvisi di nuovo ingresso nella Sala Direttivo';
  assert (select count(*) from net.calls) > (select n from n0), 'le notifiche ripartono';
end $$;

-- In alternativa (password dimenticata): il primo Direttivo nominato dall'editor SQL.
select set_config('request.jwt.claim.sub', '', false);
begin;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c3', 'editor@example.com');
update profiles set club_role = 'direttivo' where id = '00000000-0000-0000-0000-0000000000c3';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', true);
do $$ begin
  assert (select complete_registration('Altro', 'Capo', 1985, 'ALTRO', null, array['milanac'],
          false, null, null, 'POR', 1, 'ps5', null)) = 'ok', 'il Direttivo nominato completa';
  assert is_direttivo(), 'e resta Direttivo';
end $$;
rollback;
SQL
echo "     Direttivo con la password, giocatore e Direttivo nominato dall'editor SQL: ok"

# ---------------------------------------------------------------- 5) Storage
echo "→ 5) svuota_storage.py (Storage finto in locale)"
if ! NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost" \
     python3 -m unittest discover -s "$DIR" -p 'test_*.py' > "$TMP/storage.txt" 2>&1; then
  cat "$TMP/storage.txt" >&2
  fail "prove di svuota_storage.py"
fi
tail -n 3 "$TMP/storage.txt" | sed 's/^/     /'

echo "Azzeramento: tutte le prove superate"
