"""Prove di svuota_storage.py contro uno Storage finto in locale (127.0.0.1, niente rete).

Lo Storage finto imita l'API vera: elenco di una cartella (sottocartelle con id nullo,
limit/offset, prefisso con o senza "/" finale) e cancellazione di al massimo 1000 file.
"""
from __future__ import annotations

import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blocchi  # noqa: E402
import svuota_storage  # noqa: E402

CHIAVE = "sb_secret_prova"


class StorageFinto(BaseHTTPRequestHandler):
    file: dict[str, set[str]] = {}
    cancellazioni: list[int] = []

    def log_message(self, *args):  # silenzio
        pass

    def _rispondi(self, codice: int, dati) -> None:
        corpo = json.dumps(dati).encode()
        self.send_response(codice)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def _corpo(self) -> dict:
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")

    def _autorizzato(self) -> bool:
        if self.headers.get("apikey") != CHIAVE or "Mozilla" in self.headers.get("User-Agent", ""):
            self._rispondi(401, {"statusCode": "401", "error": "Unauthorized", "message": "chiave"})
            return False
        return True

    def do_POST(self):
        if not self._autorizzato():
            return
        bucket = self.path.removeprefix("/storage/v1/object/list/")
        corpo = self._corpo()
        prefisso = corpo.get("prefix", "")
        if prefisso and not prefisso.endswith("/"):
            prefisso += "/"
        figli: dict[str, dict] = {}
        for p in self.file.get(bucket, set()):
            if not p.startswith(prefisso):
                continue
            resto = p[len(prefisso):]
            if "/" in resto:
                nome = resto.split("/")[0]
                figli[nome] = {"name": nome, "id": None, "metadata": None}
            else:
                figli[resto] = {"name": resto, "id": f"id-{p}", "metadata": {"size": 1}}
        voci = [figli[k] for k in sorted(figli)]
        inizio = corpo.get("offset", 0)
        self._rispondi(200, voci[inizio:inizio + corpo.get("limit", 100)])

    def do_DELETE(self):
        if not self._autorizzato():
            return
        bucket = self.path.removeprefix("/storage/v1/object/")
        percorsi = self._corpo().get("prefixes", [])
        if len(percorsi) > 1000:
            self._rispondi(400, {"statusCode": "400", "error": "Too many"})
            return
        presenti = self.file.get(bucket, set())
        tolti = [p for p in percorsi if p in presenti]
        presenti.difference_update(tolti)
        self.cancellazioni.append(len(percorsi))
        self._rispondi(200, [{"name": p, "bucket_id": bucket} for p in tolti])


class ProvaSvuotaStorage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), StorageFinto)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        StorageFinto.cancellazioni = []
        StorageFinto.file = {
            # 2500 file nella stessa cartella: più pagine da 1000.
            "chat": {f"utente-1/{i:04d}.jpg" for i in range(2500)}
                    | {"utente-2/vocale.m4a", "utente-2/replay/azioni.json", "utente-2/replay/voce.m4a"},
            "avatars": {"utente-1/foto_1.jpg", "utente-2/foto_9.jpg", ".emptyFolderPlaceholder",
                        "a/b/c/d/profondo.png"},
            "trophies": {"coppa.png"},
        }
        self.righe: list[str] = []

    def lancia(self, **env) -> int:
        base = {"SUPABASE_URL": self.url, "SUPABASE_SECRET_KEY": CHIAVE, "BUCKETS": "chat,avatars"}
        return svuota_storage.main({**base, **env}, stampa=self.righe.append)

    def test_prova_conta_e_non_cancella(self):
        self.assertEqual(self.lancia(), 0)  # DRY_RUN mancante = prova
        self.assertIn("chat: 2503 file (prova: nessuno cancellato)", self.righe)
        self.assertIn("avatars: 4 file (prova: nessuno cancellato)", self.righe)
        self.assertEqual(StorageFinto.cancellazioni, [])
        self.assertEqual(len(StorageFinto.file["chat"]), 2503)

    def test_svuota_tutto_a_gruppi_e_solo_i_bucket_scelti(self):
        self.assertEqual(self.lancia(DRY_RUN="0", CONFERMA="AZZERA"), 0)
        self.assertEqual(StorageFinto.file["chat"], set())
        self.assertEqual(StorageFinto.file["avatars"], set())
        self.assertEqual(StorageFinto.file["trophies"], {"coppa.png"})
        self.assertTrue(all(n <= svuota_storage.GRUPPO for n in StorageFinto.cancellazioni))
        self.assertIn("chat: 2503 file, 2503 cancellati, 0 rimasti", self.righe)
        self.assertFalse(any("utente-" in r or ".jpg" in r for r in self.righe), "mai nomi di file")

    def test_senza_conferma_non_cancella(self):
        self.assertEqual(self.lancia(DRY_RUN="0"), 1)
        self.assertEqual(StorageFinto.cancellazioni, [])

    def test_chiave_sbagliata(self):
        self.assertEqual(self.lancia(SUPABASE_SECRET_KEY="sb_secret_altra"), 1)
        self.assertTrue(any("401" in r and "Unauthorized" in r for r in self.righe))

    def test_bucket_presi_dai_blocchi(self):
        testo = "\n".join([
            "begin;",
            "-- ==== BLOCCO account · obbligatorio · file: avatars, chat", "delete from a;",
            "-- ==== FINE account",
            "-- ==== BLOCCO partite · da decidere · file: match-media", "delete from b;",
            "-- ==== FINE partite",
            "-- ==== BLOCCO notizie · da decidere", "delete from c;", "-- ==== FINE notizie",
            "commit;"])
        self.assertEqual(blocchi.bucket_da_svuotare(testo), ["avatars", "chat", "match-media"])
        # Tolto un blocco da decidere, il suo bucket non si tocca più.
        senza = blocchi.senza(testo, {"partite"})
        self.assertEqual(blocchi.bucket_da_svuotare(senza), ["avatars", "chat"])
        self.assertNotIn("delete from b;", senza)
        with self.assertRaises(ValueError):
            blocchi.senza(testo, {"account"})
        # Il file vero: sempre i bucket dei membri, nessun bucket del club senza un blocco.
        vero = blocchi.bucket_da_svuotare(blocchi.FILE_SQL.read_text(encoding="utf-8"))
        self.assertEqual(vero[:2], ["avatars", "chat"])
        self.assertNotIn("trophies", vero)


if __name__ == "__main__":
    unittest.main()
