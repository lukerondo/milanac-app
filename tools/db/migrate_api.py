#!/usr/bin/env python3
"""Applica le migrazioni di supabase/migrations/ tramite la Management API di Supabase.

Alternativa a migrate.sh che non richiede la password del database:
basta un token di accesso personale (supabase.com/dashboard/account/tokens).

Variabili d'ambiente:
  SUPABASE_ACCESS_TOKEN   token personale (sbp_...), secret di GitHub
  SUPABASE_PROJECT_REF    riferimento del progetto (es. bxtnvgnxfyzwamfdnmkx)
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def query(ref: str, token: str, sql: str) -> list:
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=json.dumps({"query": sql}).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "milanac-migrate/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read().decode() or "[]"
            return json.loads(body)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if e.code == 401:
            raise SystemExit("Token non valido o scaduto (SUPABASE_ACCESS_TOKEN).") from None
        raise SystemExit(f"Errore {e.code} da Supabase: {detail}") from None


def main() -> int:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    if not token.startswith("sbp_"):
        print("::error::SUPABASE_ACCESS_TOKEN deve iniziare con sbp_ "
              "(token personale da supabase.com/dashboard/account/tokens)")
        return 1

    query(ref, token, """
        create table if not exists public.schema_migrations (
          version text primary key,
          applied_at timestamptz not null default now()
        );
        alter table public.schema_migrations enable row level security;""")
    done = {r["version"] for r in query(ref, token, "select version from public.schema_migrations")}

    applied = 0
    for file in sorted((ROOT / "supabase" / "migrations").glob("*.sql")):
        version = file.stem
        if version in done:
            print(f"• {version}: già applicata")
            continue
        print(f"▶ {version}: in esecuzione…", flush=True)
        # Tutto il file + la registrazione in un'unica transazione.
        sql = (f"begin;\n{file.read_text(encoding='utf-8')}\n"
               f"insert into public.schema_migrations (version) values ('{version}');\ncommit;")
        query(ref, token, sql)
        print(f"✓ {version}: applicata")
        applied += 1
    print(f"Fatto: {applied} migrazioni applicate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
