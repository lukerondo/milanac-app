#!/usr/bin/env python3
"""Svuota i bucket dello Storage dei membri, dopo azzera.sql.

Da SQL i file non si possono cancellare (Supabase lo blocca): qui si usa l'API di Storage,
elencando ogni cartella (anche le sottocartelle) e cancellando a gruppi. Alla fine si
ricontrolla che il bucket sia vuoto.
I bucket sono quelli dei blocchi presenti in azzera.sql (voce "file:"): se un blocco da
decidere è stato tolto, i suoi file restano. BUCKETS li sostituisce.

Variabili d'ambiente:
  SUPABASE_URL          es. https://xxxx.supabase.co
  SUPABASE_SECRET_KEY   chiave segreta (sb_secret_...), salvata nei Secrets di GitHub
  DRY_RUN               1 = conta soltanto (predefinito), 0 = cancella
  CONFERMA              deve valere AZZERA per cancellare
  BUCKETS               facoltativo: bucket separati da virgole, al posto di quelli di azzera.sql
Stampa solo numeri, mai nomi di file (i log di GitHub Actions sono pubblici).
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Callable, Iterator

import blocchi

# Come per le notizie: niente User-Agent da browser con le chiavi sb_secret_.
USER_AGENT = "milanac-azzeramento/1.0 (+https://github.com/lukerondo/milanac-app)"
PAGINA = 1000   # voci per ogni elenco
GRUPPO = 100    # file per ogni cancellazione (l'API ne accetta fino a 1000)
GIRI = 3        # elenca e cancella finché il bucket non è vuoto, al massimo tre volte


class ErroreStorage(Exception):
    pass


class Storage:
    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/") + "/storage/v1"
        self.headers = {"apikey": key, "Content-Type": "application/json", "User-Agent": USER_AGENT}
        if not key.startswith("sb_"):  # vecchia chiave service_role (JWT)
            self.headers["Authorization"] = f"Bearer {key}"

    def _chiama(self, metodo: str, percorso: str, corpo: dict) -> list:
        req = urllib.request.Request(self.base + percorso, data=json.dumps(corpo).encode(),
                                     method=metodo, headers=self.headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode() or "[]") or []
        except urllib.error.HTTPError as e:
            # Solo il tipo d'errore (es. "Bucket not found"): il messaggio può contenere percorsi.
            try:
                tipo = str(json.loads(e.read().decode(errors="replace")).get("error", ""))[:60]
            except (ValueError, AttributeError):
                tipo = ""
            raise ErroreStorage(f"{metodo} {percorso}: errore {e.code} {tipo}".rstrip()) from None
        except urllib.error.URLError as e:
            raise ErroreStorage(f"Storage non raggiungibile: {e.reason}") from None

    def _voci(self, bucket: str, cartella: str) -> Iterator[dict]:
        offset = 0
        while True:
            voci = self._chiama("POST", f"/object/list/{urllib.parse.quote(bucket)}", {
                "prefix": f"{cartella}/" if cartella else "",
                "limit": PAGINA, "offset": offset,
                "sortBy": {"column": "name", "order": "asc"},
            })
            yield from voci
            if len(voci) < PAGINA:
                return
            offset += PAGINA

    def file(self, bucket: str) -> list[str]:
        """Tutti i file del bucket, cartella per cartella (le cartelle hanno id nullo)."""
        trovati: list[str] = []
        da_vedere, viste = [""], set()
        while da_vedere:
            cartella = da_vedere.pop()
            if cartella in viste:
                continue
            viste.add(cartella)
            for voce in self._voci(bucket, cartella):
                nome = voce.get("name") or ""
                if not nome:
                    continue
                percorso = f"{cartella}/{nome}" if cartella else nome
                if voce.get("id") is None:
                    da_vedere.append(percorso)
                else:
                    trovati.append(percorso)
        return trovati

    def cancella(self, bucket: str, percorsi: list[str]) -> int:
        tolti = 0
        for i in range(0, len(percorsi), GRUPPO):
            risposta = self._chiama("DELETE", f"/object/{urllib.parse.quote(bucket)}",
                                    {"prefixes": percorsi[i:i + GRUPPO]})
            tolti += len(risposta)
        return tolti


def svuota(storage: Storage, bucket_: list[str], prova: bool,
           stampa: Callable[[str], None] = print) -> int:
    rimasti_in_tutto = 0
    for bucket in bucket_:
        trovati = storage.file(bucket)
        if prova:
            stampa(f"{bucket}: {len(trovati)} file (prova: nessuno cancellato)")
            continue
        tolti, rimasti = 0, trovati
        for _ in range(GIRI):
            if not rimasti:
                break
            tolti += storage.cancella(bucket, rimasti)
            rimasti = storage.file(bucket)
        stampa(f"{bucket}: {len(trovati)} file, {tolti} cancellati, {len(rimasti)} rimasti")
        rimasti_in_tutto += len(rimasti)
    return rimasti_in_tutto


def main(env: dict[str, str] | None = None, stampa: Callable[[str], None] = print) -> int:
    env = dict(os.environ if env is None else env)
    url = env.get("SUPABASE_URL", "").strip()
    key = env.get("SUPABASE_SECRET_KEY", "").strip()
    prova = env.get("DRY_RUN", "1") != "0"
    if not url.startswith(("https://", "http://")) or not key:
        stampa("SUPABASE_URL o SUPABASE_SECRET_KEY mancanti")
        return 1
    if not prova and env.get("CONFERMA") != "AZZERA":
        stampa("Per cancellare davvero serve CONFERMA=AZZERA")
        return 1
    scelti = [b.strip() for b in env.get("BUCKETS", "").split(",") if b.strip()]
    bucket_ = scelti or blocchi.bucket_da_svuotare(blocchi.FILE_SQL.read_text(encoding="utf-8"))
    stampa(("Prova" if prova else "Svuotamento") + " dei bucket: " + ", ".join(bucket_))
    try:
        rimasti = svuota(Storage(url, key), bucket_, prova, stampa)
    except ErroreStorage as e:
        stampa(f"Errore: {e}")
        return 1
    if rimasti:
        stampa(f"Restano {rimasti} file: rilancia il workflow per riprovare")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
