#!/usr/bin/env python3
"""Diagnostica in sola lettura del database.

I log di GitHub Actions del repository sono pubblici: qui si stampano solo conteggi e
impostazioni, mai nomi, ruoli dei singoli membri, email o id.

Simula l'approvazione di un utente in attesa da parte del Direttivo dentro una
transazione annullata (rollback), per capire se i permessi la consentono.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from migrate_api import query  # noqa: E402

ref = os.environ["SUPABASE_PROJECT_REF"]
token = os.environ["SUPABASE_ACCESS_TOKEN"]


def show(title: str, sql: str) -> list:
    print(f"\n== {title}")
    try:
        rows = query(ref, token, sql)
    except SystemExit as e:
        print(f"ERRORE: {e}")
        return []
    for r in rows:
        print("  ", json.dumps(r, ensure_ascii=False, default=str))
    if not rows:
        print("   (nessuna riga)")
    return rows


show("Profili per ruolo e stato (solo conteggi)",
     "select club_role, active, count(*) as profili from public.profiles "
     "group by club_role, active order by club_role, active")
show("Permessi su profiles e profile_private",
     "select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) as privilegi "
     "from information_schema.role_table_grants where table_schema='public' "
     "and table_name in ('profiles', 'profile_private') "
     "and grantee in ('anon','authenticated') group by table_name, grantee order by 1, 2")
show("Proprietari delle funzioni di sicurezza",
     "select p.proname, r.rolname as owner, p.prosecdef as security_definer from pg_proc p "
     "join pg_roles r on r.oid = p.proowner where p.proname in "
     "('is_direttivo','is_member','prevent_self_role_change','handle_new_user','delete_my_account')")
show("Tabelle in realtime",
     "select tablename from pg_publication_tables where pubname = 'supabase_realtime'")

direttivo = query(ref, token, "select id from public.profiles where club_role = 'direttivo' limit 1")
pending = query(ref, token, "select id from public.profiles where club_role = 'pending' limit 1")
if direttivo and pending:
    d, p = direttivo[0]["id"], pending[0]["id"]
    claims = json.dumps({"sub": d, "role": "authenticated"})
    show("Prova approvazione come Direttivo (annullata con rollback)", f"""
      begin;
      set local role authenticated;
      select set_config('request.jwt.claims', '{claims}', true);
      select set_config('request.jwt.claim.sub', '{d}', true);
      with r as (
        update public.profiles set club_role = 'giocatore', joined_at = current_date
        where id = '{p}' returning id
      )
      select (select auth.uid()::text = '{d}') as uid_ok,
             (select public.is_direttivo()) as is_direttivo,
             (select count(*) from r) as righe_aggiornate;
      rollback;""")
else:
    print("\n(nessun utente in attesa o nessun direttivo: prova di approvazione saltata)")
