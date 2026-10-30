#!/usr/bin/env python3
"""Prepara l'account sviluppatore Apple per l'IPA ad hoc, con la chiave API di App Store Connect.

- Crea l'identificativo dell'app (com.milanacproclub.milanac) se manca.
- Registra gli iPhone del secret IOS_DISPOSITIVI che non ci sono ancora (il repository è pubblico:
  gli UDID non vanno nei file). Quelli registrati a mano su developer.apple.com valgono lo stesso.
- Scrive in $GITHUB_OUTPUT il Team ID e quanti iPhone sono registrati (il profilo Ad Hoc li
  comprende tutti; lo crea Xcode durante la firma).
Stampa solo nomi e numeri: i log di GitHub Actions sono pubblici, gli UDID no.

Variabili d'ambiente:
  ASC_KEY_ID, ASC_ISSUER_ID   chiave API di App Store Connect (ruolo Admin)
  ASC_KEY_P8                  contenuto del file .p8 della chiave
  IOS_DISPOSITIVI             facoltativo: una riga per iPhone, "Nome;UDID"
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT (con cryptography): firma ES256 del token

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.milanacproclub.milanac"
UDID = re.compile(r"^[0-9A-Fa-f]{8}-?[0-9A-Fa-f]{16}$|^[0-9A-Fa-f]{40}$")


def token() -> str:
    key = os.environ["ASC_KEY_P8"].strip()
    if "BEGIN PRIVATE KEY" not in key:
        raise SystemExit("::error::ASC_KEY_P8 deve contenere il file .p8 così com'è (BEGIN PRIVATE KEY…)")
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 15 * 60,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"})


def call(method: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        path if path.startswith("http") else API + path,
        data=None if body is None else json.dumps(body).encode(), method=method,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if e.code == 401:
            raise SystemExit("::error::Chiave API rifiutata da Apple: controlla ASC_KEY_ID, "
                             "ASC_ISSUER_ID e ASC_KEY_P8") from None
        if e.code == 403:
            raise SystemExit("::error::La chiave API non ha i permessi: serve il ruolo Admin") from None
        raise SystemExit(f"::error::Apple ha risposto {e.code} a {method} {path}: {detail[:500]}") from None


def all_pages(path: str) -> list[dict]:
    out, url = [], path
    while url:
        page = call("GET", url)
        out += page.get("data", [])
        url = page.get("links", {}).get("next")
    return out


def bundle_id() -> dict:
    q = urllib.parse.urlencode({"filter[identifier]": BUNDLE_ID, "limit": 200})
    for b in all_pages(f"/bundleIds?{q}"):
        if b["attributes"]["identifier"] == BUNDLE_ID:
            return b
    print(f"Identificativo {BUNDLE_ID} assente: lo creo.")
    return call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE_ID, "name": "MILANAC", "platform": "IOS"}}})["data"]


def wanted_devices() -> list[tuple[str, str]]:
    """(nome, UDID) dal secret IOS_DISPOSITIVI: una riga per iPhone, "Nome;UDID"."""
    out = []
    for n, line in enumerate(os.environ.get("IOS_DISPOSITIVI", "").splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        name, _, udid = (p.strip() for p in line.rpartition(";"))
        if not name or not UDID.match(udid):
            raise SystemExit(f"::error::IOS_DISPOSITIVI riga {n}: serve \"Nome;UDID\"")
        out.append((name[:50], udid))
    return out


def main() -> int:
    for v in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(v, "").strip():
            raise SystemExit(f"::error::Manca il secret {v}")
    bundle = bundle_id()
    team = bundle["attributes"].get("seedId", "")
    if not re.fullmatch(r"[A-Z0-9]{10}", team or ""):
        raise SystemExit("::error::Team ID non trovato nell'identificativo dell'app")

    registered = all_pages("/devices?limit=200")
    known = {d["attributes"]["udid"].upper().replace("-", "") for d in registered}
    added = 0
    for name, udid in wanted_devices():
        if udid.upper().replace("-", "") in known:
            continue
        call("POST", "/devices", {"data": {"type": "devices", "attributes": {
            "name": name, "udid": udid, "platform": "IOS"}}})
        print(f"Registrato l'iPhone di {name}.")
        added += 1
    iphones = [d for d in all_pages("/devices?limit=200")
               if d["attributes"].get("platform") == "IOS"
               and d["attributes"].get("status") == "ENABLED"
               and d["attributes"].get("deviceClass") in ("IPHONE", "IPAD", "IPOD")]
    print(f"Team {team}: {len(iphones)} dispositivi iOS registrati ({added} nuovi).")
    if not iphones:
        raise SystemExit("::error::Nessun iPhone registrato: metti gli UDID nel secret IOS_DISPOSITIVI")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"team={team}\ndispositivi={len(iphones)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
