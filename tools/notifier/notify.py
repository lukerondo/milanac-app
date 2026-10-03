#!/usr/bin/env python3
"""Notifiche push del MILANAC Pro Club tramite Firebase Cloud Messaging (topic "milanac").

Modalità:
  python notify.py novita      → nuovi Title Update e nuovi eventi in calendario (dopo il job notizie)
  python notify.py promemoria  → promemoria presenze nel giorno di partita/allenamento

Variabili d'ambiente:
  SUPABASE_URL, SUPABASE_SECRET_KEY   database (Secrets di GitHub)
  FIREBASE_SERVICE_ACCOUNT            JSON dell'account di servizio Firebase (Secret di GitHub)
  DRY_RUN=1                           mostra le notifiche senza inviarle

Senza FIREBASE_SERVICE_ACCOUNT il job termina senza errori (notifiche non ancora configurate).
"""
from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

ROME = ZoneInfo("Europe/Rome")
TOPIC = "milanac"
REMINDER_TYPES = ("torneo", "amichevole", "allenamento")
EVENT_LABELS = {
    "torneo": "Partita di torneo",
    "amichevole": "Amichevole",
    "allenamento": "Allenamento",
    "riunione": "Riunione",
    "altro": "Evento",
}
GIORNI = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]


# ----------------------------------------------------------------------------- testi

def update_message(news: list[dict]) -> dict | None:
    if not news:
        return None
    latest = max(news, key=lambda n: n["published_at"])
    return {
        "title": "🔄 Nuovo aggiornamento FC 27",
        "body": f"{latest['title']} — aggiorna il gioco prima del match!",
        "route": "/",
    }


def event_message(event: dict) -> dict:
    start = datetime.fromisoformat(event["starts_at"]).astimezone(ROME)
    label = EVENT_LABELS.get(event["type"], "Evento")
    when = f"{GIORNI[start.weekday()]} {start.day}/{start.month} alle {start:%H:%M}"
    return {
        "title": f"📅 Nuovo in calendario: {label}",
        "body": f"{event['title']} · {when}",
        "route": "/calendario",
    }


def reminder_message(events: list[dict]) -> dict | None:
    if not events:
        return None
    first = min(events, key=lambda e: e["starts_at"])
    start = datetime.fromisoformat(first["starts_at"]).astimezone(ROME)
    others = f" (+{len(events) - 1} altri eventi)" if len(events) > 1 else ""
    return {
        "title": f"⚽ Stasera alle {start:%H:%M}: {first['title']}{others}",
        "body": "Segna la tua presenza nell'app. Se arrivi più tardi indica l'orario!",
        "route": "/presenze",
    }


# ----------------------------------------------------------------------------- servizi

def http(method: str, url: str, headers: dict, body: dict | list | None = None) -> bytes:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=25) as resp:
        return resp.read()


class Supabase:
    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/") + "/rest/v1"
        # User-Agent non da browser: Supabase rifiuta le chiavi sb_secret_ dai browser.
        self.headers = {"apikey": key, "User-Agent": "milanac-notifier/1.0"}

    def select(self, table: str, query: dict) -> list[dict]:
        qs = urllib.parse.urlencode(query, safe="(),.:*")
        return json.loads(http("GET", f"{self.base}/{table}?{qs}", self.headers))

    def mark_notified(self, table: str, ids: list) -> None:
        if not ids:
            return
        in_list = ",".join(str(i) for i in ids)
        http("PATCH", f"{self.base}/{table}?id=in.({in_list})",
             {**self.headers, "Prefer": "return=minimal"},
             {"notified_at": datetime.now(timezone.utc).isoformat()})


class Fcm:
    def __init__(self, service_account: dict):
        # google-auth firma il token OAuth dell'account di servizio.
        from google.oauth2 import service_account as sa
        import google.auth.transport.requests as gr

        creds = sa.Credentials.from_service_account_info(
            service_account, scopes=["https://www.googleapis.com/auth/firebase.messaging"])
        creds.refresh(gr.Request())
        self.token = creds.token
        self.url = f"https://fcm.googleapis.com/v1/projects/{service_account['project_id']}/messages:send"

    def send(self, msg: dict) -> None:
        http("POST", self.url, {"Authorization": f"Bearer {self.token}"}, {
            "message": {
                "topic": TOPIC,
                "notification": {"title": msg["title"], "body": msg["body"]},
                "data": {"route": msg["route"]},
                "android": {"priority": "high", "notification": {"color": "#C8102E"}},
                "apns": {"payload": {"aps": {"sound": "default"}}},
            }
        })


# ----------------------------------------------------------------------------- modalità

def run_novita(db: Supabase, send) -> None:
    since = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat()
    news = db.select("news", {
        "select": "id,title,published_at",
        "category": "eq.aggiornamenti",
        "notified_at": "is.null",
        "published_at": f"gte.{since}",
    })
    msg = update_message(news)
    if msg:
        send(msg)
    db.mark_notified("news", [n["id"] for n in news])

    events = db.select("events", {
        "select": "id,type,title,starts_at",
        "notified_at": "is.null",
        "created_at": f"gte.{since}",
        "starts_at": f"gte.{datetime.now(timezone.utc).isoformat()}",
    })
    for e in events:
        send(event_message(e))
    db.mark_notified("events", [e["id"] for e in events])


def todays_events(db: Supabase, now: datetime) -> list[dict]:
    day_start = now.astimezone(ROME).replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = day_start + timedelta(days=1)
    events = db.select("events", {
        "select": "id,type,title,starts_at",
        "and": f"(starts_at.gte.{day_start.isoformat()},starts_at.lt.{day_end.isoformat()})",
        "type": f"in.({','.join(REMINDER_TYPES)})",
    })
    # Solo eventi serali non ancora iniziati.
    return [e for e in events if datetime.fromisoformat(e["starts_at"]) > now]


def run_promemoria(db: Supabase, send) -> None:
    msg = reminder_message(todays_events(db, datetime.now(timezone.utc)))
    if msg:
        send(msg)
    else:
        print("Nessun evento oggi: nessun promemoria.")


def main(mode: str) -> int:
    dry_run = os.environ.get("DRY_RUN") == "1"
    account = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if not account and not dry_run:
        print("FIREBASE_SERVICE_ACCOUNT non impostato: notifiche push non ancora configurate.")
        return 0
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SECRET_KEY")
    if not url or not key:
        print("SUPABASE_URL o SUPABASE_SECRET_KEY mancanti", file=sys.stderr)
        return 1

    if dry_run:
        def send(m):
            print(f"[prova] {m['title']} | {m['body']}")
    else:
        fcm = Fcm(json.loads(account))

        def send(m):
            fcm.send(m)
            print(f"Inviata: {m['title']}")

    db = Supabase(url, key)
    if dry_run:
        db.mark_notified = lambda table, ids: print(f"[prova] {len(ids)} {table} da segnare come notificati")
    {"novita": run_novita, "promemoria": run_promemoria}[mode](db, send)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("novita", "promemoria"):
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
