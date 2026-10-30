#!/usr/bin/env python3
"""esegui.py come lo lancia il workflow, ma con la Management API sostituita da psql sul
database locale di prova_locale.sh (PGDATABASE): stesso SQL e stessi errori, nessuna rete.
Usato solo da prova_locale.sh.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import esegui  # noqa: E402

PSQL = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"]


def query_locale(ref: str, token: str, sql: str) -> list:
    if sql.strip() == esegui.CONTEGGI:
        sql = f"select coalesce(json_agg(t), '[]') from ({esegui.CONTEGGI}) t"
        return json.loads(subprocess.run(PSQL, input=sql, text=True, capture_output=True,
                                         check=True).stdout)
    r = subprocess.run(PSQL, input=sql, text=True, capture_output=True)
    if r.returncode != 0:  # come migrate_api.query con una risposta HTTP 400
        raise SystemExit(f"Errore 400 da Supabase: {json.dumps({'message': r.stderr.strip()})}")
    return []


if __name__ == "__main__":
    if not os.environ.get("PGDATABASE"):
        sys.exit("Serve PGDATABASE (il database di prova)")
    esegui.query = query_locale
    os.environ["SUPABASE_ACCESS_TOKEN"] = "sbp_prova_locale"
    os.environ["SUPABASE_PROJECT_REF"] = "provalocale0000"
    sys.argv = sys.argv[:1]
    sys.exit(esegui.main())
