#!/usr/bin/env python3
"""TestFlight con la chiave API di App Store Connect (la stessa del workflow iPhone).

Due passi, chiamati dal workflow TestFlight:

  testflight.py prepara      trova l'app su App Store Connect (bundle com.milanacproclub.milanac,
                             va creata una volta a mano dal sito) e sceglie il numero della build:
                             uno più dell'ultima caricata. Scrive app e build in $GITHUB_OUTPUT.
  testflight.py distribuisci aspetta che Apple finisca di elaborare la build caricata, la mette
                             nel gruppo di tester esterni "Club" (lo crea se manca, con il link
                             pubblico attivo), scrive il "Cosa testare" della build (NOVITA, o un
                             testo standard dove manca) e la manda alla revisione beta di Apple.
                             Se mancano informazioni sul test dice quali campi (solo i nomi) e si
                             ferma senza errore: la build è comunque pronta per i tester interni.

Stampa solo nomi, numeri e stati: i log di GitHub Actions sono pubblici. Il link pubblico di
TestFlight non si stampa (chi lo trova potrebbe iscriversi): si copia da App Store Connect.

Variabili d'ambiente: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8; per "distribuisci" anche APP_ID e
BUILD_NUMBER (dati da "prepara", o il numero di una build già caricata) e, facoltativo, NOVITA.
"""
from __future__ import annotations

import os
import sys
import time
import urllib.parse
from typing import Callable

BUNDLE_ID = "com.milanacproclub.milanac"
GROUP = "Club"

Call = Callable[..., dict]
Pages = Callable[[str], list]


def find_app(pages: Pages) -> dict:
    q = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "limit": 200})
    for app in pages(f"/apps?{q}"):
        if app["attributes"].get("bundleId") == BUNDLE_ID:
            return app
    raise SystemExit(
        f"::error::Su App Store Connect non c'è un'app con il bundle {BUNDLE_ID}: creala da "
        "appstoreconnect.apple.com → App → + → Nuova app (vedi docs/PUBBLICAZIONE.md, TestFlight).")


def next_build_number(pages: Pages, app_id: str) -> int:
    """Uno più della build più alta già caricata (Apple rifiuta un numero già usato)."""
    q = urllib.parse.urlencode({"filter[app]": app_id, "sort": "-uploadedDate", "limit": 200,
                                "fields[builds]": "version"})
    highest = 0
    for b in pages(f"/builds?{q}"):
        version = str(b["attributes"].get("version") or "")
        if version.isdigit():
            highest = max(highest, int(version))
    return highest + 1


def wait_for_build(pages: Pages, app_id: str, number: str, *, timeout: float = 45 * 60,
                   pause: float = 30, sleep: Callable[[float], None] = time.sleep) -> dict:
    """La build caricata, quando Apple ha finito di elaborarla (stato VALID)."""
    q = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": number, "limit": 10})
    waited = 0.0
    while True:
        builds = pages(f"/builds?{q}")
        if builds:
            state = builds[0]["attributes"].get("processingState")
            if state == "VALID":
                return builds[0]
            if state in ("FAILED", "INVALID"):
                raise SystemExit(f"::error::Apple ha scartato la build {number} ({state}): "
                                 "guarda l'email di App Store Connect per il motivo.")
            print(f"Build {number}: {state}.")
        else:
            print(f"Build {number}: non ancora visibile su App Store Connect.")
        if waited >= timeout:
            raise SystemExit(f"::error::La build {number} non è pronta dopo {int(timeout / 60)} "
                             "minuti: rilancia solo la distribuzione più tardi.")
        sleep(pause)
        waited += pause


def external_group(call: Call, pages: Pages, app_id: str) -> dict:
    q = urllib.parse.urlencode({"filter[app]": app_id, "limit": 200})
    for g in pages(f"/betaGroups?{q}"):
        if g["attributes"].get("name") == GROUP and not g["attributes"].get("isInternalGroup"):
            return g
    print(f"Gruppo di tester \"{GROUP}\" assente: lo creo, con il link pubblico.")
    return call("POST", "/betaGroups", {"data": {
        "type": "betaGroups",
        "attributes": {"name": GROUP, "publicLinkEnabled": True, "publicLinkLimitEnabled": False,
                       "feedbackEnabled": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
    }})["data"]


def what_to_test(call: Call, pages: Pages, build_id: str, locale: str, text: str,
                 overwrite: bool = False) -> None:
    """Il testo "Cosa testare" della build: per i tester esterni Apple lo vuole prima della
    revisione beta. Si scrive dove manca (o ovunque, con [overwrite])."""
    locs = pages(f"/builds/{build_id}/betaBuildLocalizations?limit=50")
    if not locs:
        call("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": locale, "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }})
        print(f"\"Cosa testare\" della build scritto ({locale}).")
        return
    for loc in locs:
        if overwrite or not (loc["attributes"].get("whatsNew") or "").strip():
            call("PATCH", f"/betaBuildLocalizations/{loc['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": loc["id"],
                "attributes": {"whatsNew": text},
            }})
            print(f"\"Cosa testare\" della build scritto ({loc['attributes'].get('locale')}).")


def _get(call: Call, path: str) -> dict:
    """Una risorsa singola ({} se Apple non la dà)."""
    try:
        return call("GET", path, quiet=True).get("data") or {}
    except ApiError:
        return {}


def missing_test_info(call: Call, pages: Pages, app_id: str, build: dict) -> list[str]:
    """Le voci di App Store Connect che la revisione beta chiede e che sono vuote: solo i nomi
    dei campi, mai i valori (i log sono pubblici)."""
    missing = []
    info = "TestFlight → Informazioni sul test"
    locs = pages(f"/apps/{app_id}/betaAppLocalizations?limit=50")
    if not locs:
        missing.append(f"{info}: descrizione dell'app beta ed email per i commenti")
    for loc in locs:
        a, lang = loc["attributes"], loc["attributes"].get("locale", "?")
        for key, label in (("description", "descrizione dell'app beta"),
                           ("feedbackEmail", "email per i commenti"),
                           ("privacyPolicyUrl", "URL dell'informativa sulla privacy")):
            if not (a.get(key) or "").strip():
                missing.append(f"{info} ({lang}): {label}")
    a = _get(call, f"/apps/{app_id}/betaAppReviewDetail").get("attributes") or {}
    review = f"{info} → Informazioni per la revisione beta"
    for key, label in (("contactFirstName", "nome del contatto"),
                       ("contactLastName", "cognome del contatto"),
                       ("contactPhone", "telefono del contatto"),
                       ("contactEmail", "email del contatto")):
        if not (a.get(key) or "").strip():
            missing.append(f"{review}: {label}")
    if a.get("demoAccountRequired"):
        for key, label in (("demoAccountName", "nome utente dell'account di prova"),
                           ("demoAccountPassword", "password dell'account di prova")):
            if not (a.get(key) or "").strip():
                missing.append(f"{review}: {label}")
    if build["attributes"].get("usesNonExemptEncryption") is None:
        missing.append("Build: conformità all'esportazione (uso della crittografia) non indicata")
    return missing


WHATS_NEW = ("Nuova versione dell'app MILANAC: provala e segnala problemi o idee con "
             "il pulsante Feedback di TestFlight.")


def distribute(call: Call, pages: Pages, app_id: str, number: str, *, whats_new: str = "",
               **wait) -> str:
    """Build nel gruppo esterno e alla revisione beta. Restituisce com'è andata, in breve."""
    build = wait_for_build(pages, app_id, number, **wait)
    group = external_group(call, pages, app_id)
    call("POST", f"/betaGroups/{group['id']}/relationships/builds",
         {"data": [{"type": "builds", "id": build["id"]}]})
    print(f"Build {number} nel gruppo \"{GROUP}\".")
    locale = (_get(call, f"/apps/{app_id}").get("attributes") or {}).get("primaryLocale") or "it"
    what_to_test(call, pages, build["id"], locale, whats_new.strip() or WHATS_NEW,
                 overwrite=bool(whats_new.strip()))
    missing = missing_test_info(call, pages, app_id, build)
    try:
        call("POST", "/betaAppReviewSubmissions", {"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}},
        }}, quiet=True)
    except ApiError as e:
        if missing:
            print(f"::warning::Revisione beta non richiesta (Apple ha risposto {e.code}). Su App "
                  "Store Connect mancano: " + "; ".join(missing) + ". Compilali e rilancia il "
                  f"workflow con \"build\" = {number} (solo distribuzione, senza ricompilare); "
                  "i tester interni la vedono già.")
        else:
            print(f"::warning::Revisione beta non richiesta (Apple ha risposto {e.code}): le "
                  "informazioni sul test risultano compilate, guarda il dettaglio qui sotto. "
                  "I tester interni la vedono già.")
        print(e.detail[:300])
        return "nel gruppo, revisione non richiesta"
    if missing:
        print("Da controllare su App Store Connect: " + "; ".join(missing) + ".")
    print(f"Build {number} mandata alla revisione beta di Apple.")
    return "in revisione"


class ApiError(Exception):
    def __init__(self, code: int, detail: str):
        super().__init__(f"{code}")
        self.code, self.detail = code, detail


def _api() -> tuple[Call, Pages, object]:
    """Le chiamate vere, con la firma della chiave API (apple_api.py)."""
    import json
    import urllib.error
    import urllib.request

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import apple_api

    def call(method: str, path: str, body: dict | None = None, quiet: bool = False) -> dict:
        if not quiet:
            return apple_api.call(method, path, body)
        req = urllib.request.Request(
            path if path.startswith("http") else apple_api.API + path,
            data=None if body is None else json.dumps(body).encode(), method=method,
            headers={"Authorization": f"Bearer {apple_api.token()}",
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            raise ApiError(e.code, e.read().decode(errors="replace")) from None

    return call, apple_api.all_pages, apple_api


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in ("prepara", "distribuisci"):
        raise SystemExit("Uso: testflight.py prepara|distribuisci")
    for v in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(v, "").strip():
            raise SystemExit(f"::error::Manca il secret {v}")
    call, pages, apple_api = _api()
    if argv[1] == "prepara":
        app = find_app(pages)
        number = next_build_number(pages, app["id"])
        team = apple_api.bundle_id()["attributes"].get("seedId", "")
        print(f"App \"{app['attributes'].get('name')}\" trovata (team {team}): la nuova build "
              f"sarà la {number}.")
        out = os.environ.get("GITHUB_OUTPUT")
        if out:
            with open(out, "a") as f:
                f.write(f"app={app['id']}\nbuild={number}\nteam={team}\n")
        return 0
    esito = distribute(call, pages, os.environ["APP_ID"], os.environ["BUILD_NUMBER"],
                       whats_new=os.environ.get("NOVITA", ""))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(f"- TestFlight, build {os.environ['BUILD_NUMBER']}: {esito}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
