#!/usr/bin/env python3
"""Raccoglie le notizie per l'app MILANAC e le salva nella tabella `news` di Supabase.

Eseguito da GitHub Actions ogni 3 ore. Usa solo la libreria standard di Python.

Variabili d'ambiente:
  SUPABASE_URL          es. https://xxxx.supabase.co
  SUPABASE_SECRET_KEY   chiave segreta (sb_secret_...), salvata nei Secrets di GitHub
  DRY_RUN=1             stampa le notizie senza salvarle

Ogni fonte è indipendente: se una non risponde viene saltata.
"""
from __future__ import annotations

import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from xml.etree import ElementTree as ET

USER_AGENT = "Mozilla/5.0 (compatible; MilanacNewsBot/1.0; +https://github.com/lukerondo/milanac-app)"
SUMMARY_MAX = 280
KEEP_DAYS = 60
DEFAULT_MAX_ITEMS = 15

# Parole chiave per riclassificare una notizia (in ordine di priorità).
CATEGORY_KEYWORDS = [
    ("aggiornamenti", ["title update", "aggiornamento", "patch", "update 1.", "hotfix", "manutenzione"]),
    ("tornei", ["fvpa", "virtual pro league", "vpl", "torneo", "tornei", "campionato", "coppa"]),
    ("pro_clubs", ["pro club", "pro clubs", "proclub", "clubs", "the grounds", "rush"]),
    ("ultimate_team", ["ultimate team", " fut ", "sbc", "evoluzion", "evolution", "toty", "pacchett"]),
]

ATOM = "{http://www.w3.org/2005/Atom}"
MEDIA = "{http://search.yahoo.com/mrss/}"


@dataclass
class NewsItem:
    source: str
    category: str
    title: str
    summary: str
    url: str
    published_at: str
    image_url: str | None = None


# ----------------------------------------------------------------------------- parsing

def clean_text(raw: str | None) -> str:
    """Toglie HTML, entità e spazi superflui."""
    if not raw:
        return ""
    text = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", raw, flags=re.S | re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def truncate(text: str, limit: int = SUMMARY_MAX) -> str:
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(",.;:-")
    return cut + "…"


def parse_date(value: str | None) -> datetime:
    if value:
        value = value.strip()
        try:
            d = parsedate_to_datetime(value)  # RSS (RFC 822)
        except (TypeError, ValueError):
            try:
                d = datetime.fromisoformat(value.replace("Z", "+00:00"))  # Atom (ISO 8601)
            except ValueError:
                d = None
        if d is not None:
            return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc)


def first_image(element: ET.Element, description: str | None) -> str | None:
    for tag in (f"{MEDIA}content", f"{MEDIA}thumbnail"):
        node = element.find(tag)
        if node is not None and node.get("url"):
            return node.get("url")
    enclosure = element.find("enclosure")
    if enclosure is not None and (enclosure.get("type") or "").startswith("image"):
        return enclosure.get("url")
    match = re.search(r'<img[^>]+src="([^"]+)"', description or "")
    return html.unescape(match.group(1)) if match else None


def parse_feed(xml_text: str, source: dict) -> list[NewsItem]:
    """Legge un feed RSS 2.0 o Atom e restituisce le notizie (senza filtri)."""
    root = ET.fromstring(xml_text)
    items: list[NewsItem] = []

    if root.tag == f"{ATOM}feed":
        for entry in root.findall(f"{ATOM}entry"):
            # Attenzione: un Element senza figli è "falso", serve il confronto con None.
            link = entry.find(f"{ATOM}link[@rel='alternate']")
            if link is None:
                link = entry.find(f"{ATOM}link")
            content = entry.findtext(f"{ATOM}summary") or entry.findtext(f"{ATOM}content")
            items.append(_make_item(
                source,
                title=entry.findtext(f"{ATOM}title"),
                description=content,
                url=link.get("href") if link is not None else None,
                date=entry.findtext(f"{ATOM}published") or entry.findtext(f"{ATOM}updated"),
                image=first_image(entry, content),
                publisher=None,
            ))
    else:
        for node in root.iter("item"):
            description = node.findtext("description")
            items.append(_make_item(
                source,
                title=node.findtext("title"),
                description=description,
                url=node.findtext("link"),
                date=node.findtext("pubDate"),
                image=first_image(node, description),
                publisher=node.findtext("source"),
            ))
    return [i for i in items if i is not None]


def _make_item(source: dict, *, title, description, url, date, image, publisher) -> NewsItem | None:
    title = clean_text(title)
    url = (url or "").strip()
    if not title or not url.startswith("http"):
        return None

    source_name = source["name"]
    if publisher:
        # Google News: il titolo termina con " - Nome testata".
        publisher = clean_text(publisher)
        source_name = publisher
        if title.endswith(f" - {publisher}"):
            title = title[: -len(f" - {publisher}")].strip()

    summary = clean_text(description)
    if publisher and (not summary or summary.startswith(title[:40])):
        # La descrizione di Google News ripete solo il titolo.
        summary = f"Leggi l'articolo completo su {publisher}."

    return NewsItem(
        source=source_name[:60],
        category=source["category"],
        title=truncate(title, 200),
        summary=truncate(summary),
        url=url,
        published_at=parse_date(date).astimezone(timezone.utc).isoformat(),
        image_url=image,
    )


# ----------------------------------------------------------------------------- filtri

def is_relevant(item: NewsItem, require: list[str] | None) -> bool:
    if not require:
        return True
    haystack = f" {item.title} {item.summary} ".lower()
    return any(word.lower() in haystack for word in require)


def classify(item: NewsItem) -> str:
    """Sceglie la categoria più specifica in base alle parole chiave, altrimenti quella della fonte."""
    haystack = f" {item.title} ".lower()
    for category, words in CATEGORY_KEYWORDS:
        if any(w in haystack for w in words):
            return category
    return item.category


def select(items: list[NewsItem], source: dict, now: datetime) -> list[NewsItem]:
    oldest = now - timedelta(days=KEEP_DAYS)
    result = []
    for item in items:
        if not is_relevant(item, source.get("require")):
            continue
        if datetime.fromisoformat(item.published_at) < oldest:
            continue
        item.category = classify(item)
        result.append(item)
    result.sort(key=lambda i: i.published_at, reverse=True)
    return result[: source.get("max_items", DEFAULT_MAX_ITEMS)]


# ----------------------------------------------------------------------------- rete

def http(method: str, url: str, *, headers: dict | None = None, body: bytes | None = None) -> bytes:
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=25) as resp:
        return resp.read()


class Supabase:
    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/") + "/rest/v1"
        self.headers = {"apikey": key, "Content-Type": "application/json"}

    def upsert_news(self, items: list[NewsItem]) -> None:
        if not items:
            return
        http("POST", f"{self.base}/news?on_conflict=url",
             headers={**self.headers, "Prefer": "resolution=ignore-duplicates,return=minimal"},
             body=json.dumps([asdict(i) for i in items]).encode())

    def delete_older_than(self, when: datetime) -> None:
        stamp = urllib.parse.quote(when.isoformat())
        http("DELETE", f"{self.base}/news?published_at=lt.{stamp}",
             headers={**self.headers, "Prefer": "return=minimal"})


# ----------------------------------------------------------------------------- main

def load_sources(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["sources"]


def run() -> int:
    sources = load_sources(Path(__file__).with_name("sources.json"))
    now = datetime.now(timezone.utc)
    dry_run = os.environ.get("DRY_RUN") == "1"

    collected: dict[str, NewsItem] = {}
    ok = 0
    for source in sources:
        try:
            raw = http("GET", source["url"]).decode("utf-8", errors="replace")
            items = select(parse_feed(raw, source), source, now)
            ok += 1
            print(f"✓ {source['name']}: {len(items)} notizie")
        except Exception as e:  # noqa: BLE001 - una fonte rotta non deve fermare le altre
            print(f"✗ {source['name']}: saltata ({e})")
            continue
        for item in items:
            # Stesso titolo da fonti diverse: teniamo la prima.
            key = re.sub(r"\W+", "", item.title.lower())[:80]
            collected.setdefault(key, item)

    items = list(collected.values())
    print(f"Totale: {len(items)} notizie da {ok}/{len(sources)} fonti")

    if dry_run:
        for i in sorted(items, key=lambda i: i.published_at, reverse=True):
            print(f"  [{i.category}] {i.title} ({i.source})")
        return 0

    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SECRET_KEY")
    if not url or not key:
        print("SUPABASE_URL o SUPABASE_SECRET_KEY mancanti", file=sys.stderr)
        return 1
    db = Supabase(url, key)
    db.upsert_news(items)
    db.delete_older_than(now - timedelta(days=KEEP_DAYS))
    print("Notizie salvate su Supabase.")
    return 0 if ok > 0 else 1


if __name__ == "__main__":
    sys.exit(run())
