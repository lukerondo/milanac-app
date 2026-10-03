#!/usr/bin/env bash
# Applica al database Supabase le migrazioni di supabase/migrations/ non ancora eseguite.
# Ogni file gira in una transazione: se fallisce, nulla viene applicato a metà.
# Uso: SUPABASE_DB_URL="postgresql://..." tools/db/migrate.sh
set -euo pipefail

: "${SUPABASE_DB_URL:?Variabile SUPABASE_DB_URL mancante (secret di GitHub)}"
cd "$(dirname "$0")/../.."
PSQL=(psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q -X)

"${PSQL[@]}" -c "
  create table if not exists public.schema_migrations (
    version text primary key,
    applied_at timestamptz not null default now()
  );
  alter table public.schema_migrations enable row level security;"

applied=0
for file in supabase/migrations/*.sql; do
  version=$(basename "$file" .sql)
  if [ "$("${PSQL[@]}" -tA -c "select 1 from public.schema_migrations where version = '$version'")" = "1" ]; then
    echo "• $version: già applicata"
    continue
  fi
  echo "▶ $version: in esecuzione…"
  "${PSQL[@]}" --single-transaction -f "$file" \
    -c "insert into public.schema_migrations (version) values ('$version')"
  echo "✓ $version: applicata"
  applied=$((applied + 1))
done
echo "Fatto: $applied migrazioni applicate."
