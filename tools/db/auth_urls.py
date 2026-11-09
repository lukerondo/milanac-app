#!/usr/bin/env python3
"""Aggiunge ai "Redirect URLs" di Supabase Auth gli indirizzi della web app.

Senza, i link delle email (conferma dell'account, password dimenticata) e gli accessi
con Google, Microsoft, Yahoo e Apple fatti dal browser non tornano alla web app.
Aggiunge soltanto: gli indirizzi già presenti (quello dell'app sul telefono) restano.

Variabili d'ambiente:
  SUPABASE_ACCESS_TOKEN   token personale (sbp_...), secret di GitHub
  SUPABASE_PROJECT_REF    riferimento del progetto
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

# Con e senza la barra finale: il browser può aprire la web app in entrambi i modi.
WEB_APP_URLS = [
    "https://milanacproclub.vercel.app/app/",
    "https://milanacproclub.vercel.app/app",
]


def merged(current: str | None, wanted: list[str]) -> tuple[str, list[str]]:
    """L'elenco di Supabase (separato da virgole) con in coda gli indirizzi mancanti."""
    urls = [u.strip() for u in (current or "").split(",") if u.strip()]
    missing = [u for u in wanted if u not in urls]
    return ",".join(urls + missing), missing


def call(ref: str, token: str, method: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/config/auth",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "milanac-migrate/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise SystemExit("Token non valido o scaduto (SUPABASE_ACCESS_TOKEN).") from None
        # Mai il corpo della risposta: la configurazione contiene dati riservati.
        raise SystemExit(f"Errore {e.code} da Supabase sulla configurazione di accesso.") from None


def main() -> int:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    if not token.startswith("sbp_"):
        print("::error::SUPABASE_ACCESS_TOKEN deve iniziare con sbp_ "
              "(token personale da supabase.com/dashboard/account/tokens)")
        return 1
    current = call(ref, token, "GET").get("uri_allow_list")
    value, missing = merged(current, WEB_APP_URLS)
    if not missing:
        print("Redirect URLs: la web app c'è già.")
        return 0
    call(ref, token, "PATCH", {"uri_allow_list": value})
    print(f"Redirect URLs: aggiunti {len(missing)} indirizzi della web app.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
