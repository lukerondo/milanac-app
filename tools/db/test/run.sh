#!/usr/bin/env bash
# Prova tutte le migrazioni su un database PostgreSQL vuoto, poi esegue i controlli di checks.sql.
# Uso: PGHOST=... PGUSER=... PGPASSWORD=... tools/db/test/run.sh
# (in CI usa il PostgreSQL già presente sul runner; in locale qualsiasi PostgreSQL 15+).
set -euo pipefail
export PGOPTIONS="-c client_min_messages=error"
cd "$(dirname "$0")/../../.."

DB="milanac_test_$$"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "create database $DB"
trap 'psql -q -d postgres -c "drop database if exists $DB with (force)" >/dev/null' EXIT

run() { psql -v ON_ERROR_STOP=1 -q -X -d "$DB" "$@"; }

run -f tools/db/test/supabase_stubs.sql
for f in supabase/migrations/*.sql; do
  echo "→ $(basename "$f")"
  # pg_net e pg_cron non esistono su un PostgreSQL normale: li sostituiscono gli stub.
  sed -E -e 's/^create extension if not exists pg_net.*$/-- (pg_net: stub di test)/' \
         -e 's/^create extension if not exists pg_cron.*$/-- (pg_cron: stub di test)/' "$f" \
    | run -1 -f -
done
echo "→ controlli"
run -f tools/db/test/checks.sql >/dev/null
echo "Migrazioni e controlli OK"
