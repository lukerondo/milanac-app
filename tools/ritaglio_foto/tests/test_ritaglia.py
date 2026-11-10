"""Prove di ritaglia.py senza modello e senza rete.

La rifinitura si prova su immagini disegnate (bastano numpy e Pillow); il giro completo contro
un Supabase finto in locale (127.0.0.1) che imita le poche chiamate usate: tabelle con i filtri
di PostgREST e Storage. Al posto di rembg c'è un modello finto che restituisce un ovale.
"""
from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import threading
import types
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ritaglia  # noqa: E402

ritaglia.PAUSA = 0  # nessuna attesa tra un tentativo e l'altro
CHIAVE = "sb_secret_prova"
ANNA = "11111111-1111-4111-8111-111111111111"
BRUNO = "22222222-2222-4222-8222-222222222222"
CARLA = "33333333-3333-4333-8333-333333333333"
SOGGETTO, SFONDO = (200, 40, 40), (30, 200, 60)


# ----------------------------------------------------------------------------- immagini disegnate

def ovale(dimensioni=(720, 900), sfumatura=4.0, extra=None) -> Image.Image:
    """Maschera con un ovale morbido al centro (il "soggetto"); extra aggiunge altri ovali."""
    w, h = dimensioni
    maschera = Image.new("L", dimensioni, 0)
    penna = ImageDraw.Draw(maschera)
    penna.ellipse((w * 0.25, h * 0.2, w * 0.75, h * 0.9), fill=255)
    for riquadro in extra or []:
        penna.ellipse(riquadro, fill=255)
    return maschera.filter(ImageFilter.GaussianBlur(sfumatura))


def foto_disegnata(maschera: Image.Image) -> Image.Image:
    """Soggetto rosso su sfondo verde, mescolati con la maschera come in una foto vera."""
    a = np.asarray(maschera, dtype=np.float32)[..., None] / 255
    punti = a * np.array(SOGGETTO, dtype=np.float32) + (1 - a) * np.array(SFONDO, dtype=np.float32)
    return Image.fromarray(np.round(punti).astype(np.uint8))


def in_jpeg(immagine: Image.Image, **opzioni) -> bytes:
    dati = io.BytesIO()
    immagine.save(dati, "JPEG", quality=90, **opzioni)
    return dati.getvalue()


def apri_webp(dati: bytes) -> np.ndarray:
    immagine = Image.open(io.BytesIO(dati))
    assert immagine.format == "WEBP" and immagine.mode == "RGBA"
    return np.asarray(immagine)


class ModelloFinto(ritaglia.Ritagliatore):
    """Al posto di rembg: la maschera la decide la prova (di norma un ovale al centro)."""

    def __init__(self, maschera=None, guasto: bool = False):
        super().__init__()
        self._crea = maschera or (lambda foto: ovale(foto.size))
        self.guasto = guasto
        self.chiamate = 0

    def maschera(self, foto):
        self.chiamate += 1
        if self.guasto:
            raise RuntimeError("modello rotto")
        return self._crea(foto)


# La "foto del membro" del giro completo: piccola (360x450) per fare in fretta, sempre 4:5.
FOTO = in_jpeg(foto_disegnata(ovale((360, 450), sfumatura=2.0)))


# ----------------------------------------------------------------------------- rifinitura

class RifinituraTest(unittest.TestCase):
    def test_stessa_tela_bordo_morbido_e_peso(self):
        maschera = ovale()
        webp = ritaglia.componi(foto_disegnata(maschera), maschera)
        self.assertEqual(webp[:4] + webp[8:12], b"RIFFWEBP")
        self.assertLess(len(webp), 300 * 1024)
        punti = apri_webp(webp)
        self.assertEqual(punti.shape, (900, 720, 4))  # stessa tela 4:5, niente ritagli o spostamenti
        alpha = punti[..., 3]
        self.assertEqual(int(alpha[:40].max()), 0)        # in alto solo sfondo: trasparente
        self.assertEqual(int(alpha[450, 300:420].min()), 255)  # il centro del soggetto è pieno
        # Il bordo è una sfumatura, non un taglio netto: molti valori intermedi e nessun salto.
        riga = alpha[450].astype(int)
        self.assertGreater(len(set(riga.tolist())), 8)
        self.assertLess(int(np.abs(np.diff(riga)).max()), 110)
        # Il centro tiene il colore della foto.
        self.assertLess(float(np.abs(punti[450, 360, :3].astype(int) - SOGGETTO).max()), 12)

    def test_via_il_colore_del_vecchio_sfondo(self):
        maschera = ovale(sfumatura=6.0)
        foto = foto_disegnata(maschera)
        punti = apri_webp(ritaglia.componi(foto, maschera)).astype(np.float32)
        fascia = (punti[..., 3] > 50) & (punti[..., 3] < 200)
        self.assertGreater(int(fascia.sum()), 2000)
        verde_foto = float(np.asarray(foto, dtype=np.float32)[..., 1][fascia].mean())
        verde_ritaglio = float(punti[..., 1][fascia].mean())
        self.assertGreater(verde_foto, 100)    # nella foto il bordo è mescolato al verde dello sfondo
        self.assertLess(verde_ritaglio, 70)    # nel ritaglio resta il rosso del soggetto
        self.assertGreater(float(punti[..., 0][fascia].mean()), 170)
        # Nessun alone: su nero e su oro chiaro il bordo è solo soggetto più sfondo nuovo.
        a = punti[..., 3:4] / 255
        for nuovo in ((0, 0, 0), (232, 201, 106)):
            composto = punti[..., :3] * a + np.array(nuovo, dtype=np.float32) * (1 - a)
            atteso = np.array(SOGGETTO, dtype=np.float32) * a + np.array(nuovo, dtype=np.float32) * (1 - a)
            self.assertLess(float(np.abs(composto - atteso)[fascia].mean()), 14)

    def test_macchie_staccate_tolte_pezzi_grandi_tenuti(self):
        # Una macchia piccola lontana dal soggetto sparisce...
        maschera = ovale(extra=[(40, 40, 70, 70)])
        alpha, tolta = ritaglia.rifinisci(np.asarray(maschera))
        self.assertEqual(float(alpha[30:80, 30:80].max()), 0.0)
        self.assertGreater(tolta, 0)
        self.assertLess(tolta, 0.01)
        self.assertGreater(float(alpha[450, 360]), 0.99)
        # ...una seconda persona accanto resta.
        maschera = ovale(extra=[(10, 500, 150, 890)])
        alpha, tolta = ritaglia.rifinisci(np.asarray(maschera))
        self.assertGreater(float(alpha[700, 80]), 0.99)
        self.assertLess(tolta, 0.0001)

    def test_fili_sottili_restano(self):
        # Una ciocca larga 3 punti che esce dal soggetto non viene tagliata dalla pulizia.
        maschera = ovale(sfumatura=1.0)
        ImageDraw.Draw(maschera).line((360, 200, 360, 60), fill=200, width=3)
        alpha, _ = ritaglia.rifinisci(np.asarray(maschera))
        self.assertGreater(float(alpha[70, 360]), 0.4)

    def test_controllo_di_qualita(self):
        def motivo(maschera) -> str:
            with self.assertRaises(ritaglia.Scartata) as scarto:
                ritaglia.componi(foto_disegnata(ovale()), maschera)
            return str(scarto.exception)

        self.assertIn("soggetto non trovato", motivo(Image.new("L", (720, 900), 0)))
        puntino = Image.new("L", (720, 900), 0)
        ImageDraw.Draw(puntino).ellipse((340, 430, 380, 470), fill=255)
        self.assertIn("soggetto non trovato", motivo(puntino))
        self.assertIn("sfondo non separato", motivo(Image.new("L", (720, 900), 255)))
        self.assertIn("contorno incerto", motivo(Image.new("L", (720, 900), 128)))
        rng = np.random.default_rng(3)
        chiazze = Image.fromarray(rng.integers(0, 256, (45, 36), dtype=np.uint8))
        self.assertIn("contorno incerto", motivo(chiazze.resize((720, 900), Image.Resampling.BICUBIC)))
        pezzi = Image.new("L", (720, 900), 0)
        penna = ImageDraw.Draw(pezzi)
        penna.ellipse((200, 200, 520, 600), fill=255)
        for x in range(20, 700, 60):
            penna.ellipse((x, 760, x + 34, 794), fill=255)
            penna.ellipse((x, 820, x + 34, 854), fill=255)
            penna.ellipse((x, 40, x + 34, 74), fill=255)
        self.assertIn("soggetto a pezzi", motivo(pezzi))
        # Mai un dato personale nel motivo: solo testo fisso e percentuali.
        self.assertRegex(motivo(Image.new("L", (720, 900), 0)), r"^[a-z ]+\(resta il \d+% dell'immagine\)$")

    def test_apri_dimensioni_e_orientamento(self):
        grande = Image.new("RGB", (1600, 2000), (10, 120, 200))
        self.assertEqual(ritaglia.apri(in_jpeg(grande)).size, (800, 1000))     # lato lungo 1000
        self.assertEqual(ritaglia.apri(FOTO).size, (360, 450))                 # mai ingrandita
        self.assertEqual(ritaglia.apri(in_jpeg(Image.new("RGB", (300, 375)))).size, (300, 375))
        # Foto di traverso con l'orientamento nell'EXIF: esce dritta, come la mostra l'app.
        coricata = Image.new("RGB", (900, 720), (0, 0, 0))
        ImageDraw.Draw(coricata).rectangle((0, 0, 449, 719), fill=(255, 255, 255))
        exif = Image.Exif()
        exif[0x0112] = 6  # da ruotare di 90 gradi in senso orario
        dritta = ritaglia.apri(in_jpeg(coricata, exif=exif))
        self.assertEqual(dritta.size, (720, 900))
        self.assertGreater(dritta.getpixel((360, 100))[0], 200)  # la metà bianca finisce in alto
        self.assertLess(dritta.getpixel((360, 800))[0], 50)
        # Stessa cosa quando la foto va anche rimpicciolita.
        coricata_grande = coricata.resize((2000, 1600))
        self.assertEqual(ritaglia.apri(in_jpeg(coricata_grande, exif=exif)).size, (800, 1000))

    def test_apri_altri_formati_e_file_rotti(self):
        trasparente = Image.new("RGBA", (400, 500), (255, 0, 0, 0))
        png = io.BytesIO()
        trasparente.save(png, "PNG")
        foto = ritaglia.apri(png.getvalue())
        self.assertEqual((foto.mode, foto.getpixel((10, 10))), ("RGB", (255, 255, 255)))
        for dati, motivo in ((b"non sono una foto", "non leggibile"), (FOTO[:2000], "non leggibile"),
                             (in_jpeg(Image.new("RGB", (40, 50))), "troppo piccola")):
            with self.assertRaises(ritaglia.Scartata) as scarto:
                ritaglia.apri(dati)
            self.assertIn(motivo, str(scarto.exception))

    def test_maschera_di_altra_misura(self):
        # Il modello può restituire una maschera più piccola: si porta alla misura della foto.
        webp = ritaglia.componi(foto_disegnata(ovale()), ovale((360, 450), sfumatura=2.0))
        self.assertEqual(apri_webp(webp).shape, (900, 720, 4))


# ----------------------------------------------------------------------------- modello

class ModelloTest(unittest.TestCase):
    """Come si chiama rembg, con rembg e onnxruntime finti (quelli veri qui non servono)."""

    def setUp(self):
        self.sessioni: list[dict] = []
        prova = self

        class Opzioni:
            enable_mem_pattern = True
            enable_cpu_mem_arena = True

        class Sessione:
            def predict(self, foto):
                return [ovale(foto.size), "altra maschera"]

        def new_session(modello="un altro modello", sess_opts=None, **altro):
            if prova.rotto:
                raise OSError("modello non scaricabile da https://esempio")
            prova.sessioni.append({"modello": modello, "opzioni": sess_opts, "altro": altro,
                                   "telemetria": os.environ.get("ORT_DISABLE_TELEMETRY")})
            return Sessione()

        self.rotto = False
        finti = {"onnxruntime": types.SimpleNamespace(SessionOptions=Opzioni),
                 "rembg": types.SimpleNamespace(new_session=new_session)}
        mock.patch.dict(sys.modules, finti).start()
        mock.patch.dict(os.environ).start()
        os.environ.pop("ORT_DISABLE_TELEMETRY", None)
        self.addCleanup(mock.patch.stopall)

    def test_modello_scelto_memoria_contenuta_e_niente_telemetria(self):
        modello = ritaglia.Ritagliatore()
        for _ in range(2):
            self.assertEqual(apri_webp(modello.ritaglia(FOTO)).shape, (450, 360, 4))
        self.assertEqual(len(self.sessioni), 1)  # il modello si carica una volta sola
        sessione = self.sessioni[0]
        # Sempre il modello scelto, mai quello predefinito di rembg (licenza non commerciale).
        self.assertEqual((sessione["modello"], sessione["altro"]), (ritaglia.MODELLO, {}))
        self.assertNotIn("bria", ritaglia.MODELLO)
        # Senza queste opzioni la memoria supera quella del runner alla seconda foto.
        self.assertFalse(sessione["opzioni"].enable_mem_pattern)
        self.assertFalse(sessione["opzioni"].enable_cpu_mem_arena)
        self.assertEqual(sessione["telemetria"], "1")
        self.assertTrue(modello.funziona())

    def test_modello_che_non_parte(self):
        self.rotto = True
        modello = ritaglia.Ritagliatore()
        with self.assertRaises(ritaglia.ModelloGuasto) as guasto:
            modello.ritaglia(FOTO)
        self.assertEqual(str(guasto.exception), "OSError")  # solo il tipo: mai indirizzi o percorsi
        self.assertFalse(modello.funziona())


# ----------------------------------------------------------------------------- Supabase finto

def _valori_in(testo: str) -> list[str]:
    """Legge un elenco in.("a","b") come fa PostgREST (virgolette e barre rovesciate)."""
    assert testo.startswith("(") and testo.endswith(")"), testo
    valori, attuale, tra_virgolette, i = [], "", False, 1
    while i < len(testo) - 1:
        c = testo[i]
        if c == "\\" and tra_virgolette:
            i += 1
            attuale += testo[i]
        elif c == '"':
            tra_virgolette = not tra_virgolette
        elif c == "," and not tra_virgolette:
            valori.append(attuale)
            attuale = ""
        else:
            attuale += c
        i += 1
    return valori + [attuale]


class SupabaseFinto(BaseHTTPRequestHandler):
    profili: list[dict] = []
    scartate: dict[str, str] = {}
    file: dict[str, bytes] = {}
    tipi: dict[str, str] = {}
    richieste: list[tuple[str, str]] = []
    intestazioni_viste: list[dict] = []
    guasti: dict[str, int] = {}       # nome dell'operazione -> codice HTTP con cui rispondere
    al_download = None                # funzione chiamata a ogni download (la foto cambia nel frattempo)
    dopo_pagina = None                # funzione chiamata dopo ogni pagina di righe
    righe_per_pagina = 1000           # come il limite di righe di PostgREST
    senza_migrazione = False

    def log_message(self, *args):  # silenzio
        pass

    # --- utilità
    def _rispondi(self, codice: int, dati=None, intestazioni: dict | None = None, grezzo: bytes | None = None) -> None:
        corpo = grezzo if grezzo is not None else (b"" if dati is None else json.dumps(dati).encode())
        self.send_response(codice)
        self.send_header("Content-Type", "application/octet-stream" if grezzo is not None else "application/json")
        self.send_header("Content-Length", str(len(corpo)))
        for nome, valore in (intestazioni or {}).items():
            self.send_header(nome, valore)
        self.end_headers()
        self.wfile.write(corpo)

    def _corpo(self) -> bytes:
        return self.rfile.read(int(self.headers.get("Content-Length", 0)))

    def _pronto(self, operazione: str) -> bool:
        """Registra la richiesta e controlla chiave, User-Agent e guasti finti."""
        cls = type(self)
        cls.richieste.append((self.command, self.path.split("?")[0]))
        cls.intestazioni_viste.append(dict(self.headers))
        if self.headers.get("apikey") != CHIAVE or "Mozilla" in self.headers.get("User-Agent", ""):
            self._rispondi(401, {"message": "Invalid API key", "hint": "chiave"})
            return False
        if operazione in cls.guasti:
            self._rispondi(cls.guasti[operazione], {"code": "XX000", "message": f"guasto su {self.path}"})
            return False
        return True

    def _filtrate(self, righe: list[dict], filtri: list[tuple[str, str]]):
        for colonna, condizione in filtri:
            if any(colonna not in r for r in righe):
                return None, colonna
            if condizione == "is.null":
                righe = [r for r in righe if r[colonna] is None]
            elif condizione == "not.is.null":
                righe = [r for r in righe if r[colonna] is not None]
            elif condizione == "is.true":
                righe = [r for r in righe if r[colonna] is True]
            elif condizione.startswith("eq."):
                righe = [r for r in righe if str(r[colonna]) == condizione[3:]]
            elif condizione.startswith("in."):
                righe = [r for r in righe if r[colonna] in _valori_in(condizione[3:])]
            else:
                raise AssertionError(f"filtro non previsto: {condizione}")
        return righe, None

    def _tabella(self):
        url = urllib.parse.urlsplit(self.path)
        tabella = url.path.removeprefix("/rest/v1/")
        parametri = urllib.parse.parse_qsl(url.query, keep_blank_values=True)
        opzioni = {k: v for k, v in parametri if k in ("select", "order", "limit", "offset", "on_conflict")}
        filtri = [(k, v) for k, v in parametri if k not in opzioni]
        cls = type(self)
        if tabella == "profiles":
            righe = cls.profili
            if cls.senza_migrazione:
                righe = [{k: v for k, v in r.items() if k != "avatar_cutout_path"} for r in righe]
        elif tabella == "cutout_failures" and not cls.senza_migrazione:
            righe = [{"avatar_path": p, "reason": m} for p, m in cls.scartate.items()]
        else:
            self._rispondi(404, {"code": "PGRST205", "message": f"Could not find the table 'public.{tabella}'"})
            return None
        return tabella, righe, filtri, opzioni

    # --- richieste
    def do_GET(self):
        if self.path.startswith("/storage/v1/object/"):
            if not self._pronto("scarica"):
                return
            percorso = urllib.parse.unquote(self.path.removeprefix("/storage/v1/object/avatars/"))
            cls = type(self)
            if cls.al_download:
                cls.al_download(percorso)
            if percorso not in cls.file:
                # Lo Storage vero risponde 400 con statusCode "404".
                self._rispondi(400, {"statusCode": "404", "error": "not_found", "message": "Object not found"})
                return
            self._rispondi(200, grezzo=cls.file[percorso])
            return
        if not self._pronto("leggi"):
            return
        trovata = self._tabella()
        if trovata is None:
            return
        _, righe, filtri, opzioni = trovata
        righe, manca = self._filtrate(righe, filtri)
        if manca:
            self._rispondi(400, {"code": "42703", "message": f"column profiles.{manca} does not exist"})
            return
        colonna = opzioni.get("order", "").split(".")[0]
        if colonna:
            righe = sorted(righe, key=lambda r: str(r[colonna]))
        inizio = int(opzioni.get("offset", 0))
        if inizio and inizio >= len(righe):  # come PostgREST: pagina oltre la fine
            self._rispondi(416, {"code": "PGRST103", "message": "Requested range not satisfiable"})
            return
        quante = min(int(opzioni.get("limit", 10 ** 6)), type(self).righe_per_pagina)
        pagina = righe[inizio:inizio + quante]
        colonne = opzioni.get("select", "*").split(",")
        if colonne != ["*"]:
            pagina = [{c: r[c] for c in colonne} for r in pagina]
        fascia = f"{inizio}-{inizio + len(pagina) - 1}" if pagina else "*"
        self._rispondi(200, pagina, {"Content-Range": f"{fascia}/{len(righe)}"})
        if type(self).dopo_pagina:
            type(self).dopo_pagina()

    def do_PATCH(self):
        if not self._pronto("assegna"):
            return
        trovata = self._tabella()
        if trovata is None:
            return
        tabella, _, filtri, _ = trovata
        assert tabella == "profiles" and self.headers.get("Prefer") == "return=representation"
        righe, manca = self._filtrate(type(self).profili, filtri)
        assert manca is None
        modifiche = json.loads(self._corpo())
        assert set(modifiche) == {"avatar_cutout_path"}, "il worker tocca solo la colonna del ritaglio"
        for riga in righe:
            riga.update(modifiche)
        self._rispondi(200, [{"id": r["id"]} for r in righe])

    def do_POST(self):
        cls = type(self)
        if self.path.startswith("/storage/v1/object/list/"):
            if not self._pronto("elenca"):
                return
            corpo = json.loads(self._corpo())
            prefisso, cerca = corpo["prefix"], corpo.get("search", "")
            nomi = sorted(p[len(prefisso):] for p in cls.file if p.startswith(prefisso))
            self._rispondi(200, [{"name": n, "id": f"id-{n}", "metadata": {}} for n in nomi if cerca in n])
        elif self.path.startswith("/storage/v1/object/"):
            if not self._pronto("carica"):
                return
            percorso = urllib.parse.unquote(self.path.removeprefix("/storage/v1/object/avatars/"))
            dati = self._corpo()
            if self.headers.get("Content-Type") not in ("image/jpeg", "image/png", "image/webp"):
                self._rispondi(400, {"statusCode": "415", "error": "invalid_mime_type", "message": "mime"})
            elif len(dati) > 5 * 1024 * 1024:
                self._rispondi(400, {"statusCode": "413", "error": "Payload too large", "message": "size"})
            elif percorso in cls.file:
                self._rispondi(400, {"statusCode": "409", "error": "Duplicate", "message": "exists"})
            else:
                cls.file[percorso] = dati
                cls.tipi[percorso] = self.headers.get("Content-Type")
                self._rispondi(200, {"Key": f"avatars/{percorso}"})
        else:
            if not self._pronto("scarta"):
                return
            trovata = self._tabella()
            if trovata is None:
                return
            riga = json.loads(self._corpo())
            assert trovata[0] == "cutout_failures" and set(riga) == {"avatar_path", "reason"}
            cls.scartate.setdefault(riga["avatar_path"], riga["reason"])
            self._rispondi(201)

    def do_DELETE(self):
        if not self._pronto("cancella"):
            return
        assert self.path == "/storage/v1/object/avatars"
        cls = type(self)
        tolti = [p for p in json.loads(self._corpo())["prefixes"] if cls.file.pop(p, None) is not None]
        self._rispondi(200, [{"name": p} for p in tolti])


def profilo(id_: str, foto: str | None, ritaglio: str | None = None, attivo: bool = True) -> dict:
    return {"id": id_, "active": attivo, "display_name": f"Nome di {id_[:4]}",
            "avatar_path": foto, "avatar_cutout_path": ritaglio}


class ConSupabaseFinto(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), SupabaseFinto)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        S = SupabaseFinto
        S.profili = [profilo(ANNA, f"{ANNA}/foto_1700000000200.jpg")]
        S.scartate, S.tipi, S.richieste, S.intestazioni_viste, S.guasti = {}, {}, [], [], {}
        S.file = {f"{ANNA}/foto_1700000000200.jpg": FOTO}
        S.al_download, S.dopo_pagina, S.righe_per_pagina, S.senza_migrazione = None, None, 1000, False
        self.righe: list[str] = []
        self.avvisi: list[str] = []

    def lancia(self, *argomenti: str, modello: ritaglia.Ritagliatore | None = None, **env) -> int:
        base = {"SUPABASE_URL": self.url, "SUPABASE_SECRET_KEY": CHIAVE}
        self.modello = modello or ModelloFinto()
        return ritaglia.main(list(argomenti), {**base, **env}, stampa=self.righe.append,
                             avvisa=self.avvisi.append, ritagliatore=self.modello)

    def metodi(self) -> set[str]:
        return {metodo for metodo, _ in SupabaseFinto.richieste}

    def ritagli(self, id_: str) -> list[str]:
        return sorted(p for p in SupabaseFinto.file if p.startswith(f"{id_}/ritaglio_"))

    def senza_dati_personali(self) -> None:
        """Nei log (pubblici) mai id, nomi, percorsi o indirizzi: solo testo fisso e numeri."""
        for riga in self.righe + self.avvisi:
            self.assertNotRegex(riga, r"[0-9a-f]{8}-[0-9a-f]{4}", riga)
            for vietato in ("foto_", "ritaglio_", ".jpg", ".webp", "/", "http", "Nome di", CHIAVE):
                self.assertNotIn(vietato, riga)


# ----------------------------------------------------------------------------- quali foto

class InAttesaTest(ConSupabaseFinto):
    def test_solo_attivi_con_foto_senza_ritaglio_e_non_scartati(self):
        S = SupabaseFinto
        S.profili = [
            profilo(ANNA, f"{ANNA}/foto_1700000000300.jpg"),
            profilo(BRUNO, f"{BRUNO}/foto_1700000000100.jpg"),
            profilo(CARLA, f"{CARLA}/foto_1700000000200.jpg"),
            profilo("44444444-4444-4444-8444-444444444444", None),                                # senza foto
            profilo("55555555-5555-4555-8555-555555555555", "55555555-5555-4555-8555-555555555555/foto_1.jpg",
                    attivo=False),                                                                # non attivo
            profilo("66666666-6666-4666-8666-666666666666", "66666666-6666-4666-8666-666666666666/foto_2.jpg",
                    ritaglio="66666666-6666-4666-8666-666666666666/ritaglio_3.webp"),             # già fatto
            profilo("77777777-7777-4777-8777-777777777777", "77777777-7777-4777-8777-777777777777/foto_4.jpg"),
        ]
        S.scartate = {"77777777-7777-4777-8777-777777777777/foto_4.jpg": "contorno incerto",
                      "altro/foto_9.jpg": "vecchio scarto"}
        attesa = ritaglia.Supabase(self.url, CHIAVE).in_attesa()
        # Dalla foto caricata per prima (i millisecondi nel nome).
        self.assertEqual(attesa, [(BRUNO, f"{BRUNO}/foto_1700000000100.jpg"),
                                  (CARLA, f"{CARLA}/foto_1700000000200.jpg"),
                                  (ANNA, f"{ANNA}/foto_1700000000300.jpg")])

    def test_percorsi_strani_ignorati(self):
        # avatar_path è testo libero: fuori dalla cartella del membro o con caratteri strani non si tocca.
        S = SupabaseFinto
        S.profili = [
            profilo(ANNA, f"{BRUNO}/foto_1.jpg"),
            profilo(BRUNO, f"{BRUNO}/../{ANNA}/foto_1.jpg"),
            profilo(CARLA, f'{CARLA}/a","b).jpg'),
            profilo("non-un-uuid", "non-un-uuid/foto_1.jpg"),
            profilo("88888888-8888-4888-8888-888888888888", "88888888-8888-4888-8888-888888888888/" + "x" * 300),
        ]
        self.assertEqual(ritaglia.Supabase(self.url, CHIAVE).in_attesa(), [])
        self.assertFalse(ritaglia.foto_valida(ANNA, None))
        self.assertTrue(ritaglia.foto_valida(ANNA, f"{ANNA}/foto_1700000000200.jpg"))

    def test_piu_pagine(self):
        S = SupabaseFinto
        ids = [f"{i:08d}-0000-4000-8000-000000000000" for i in range(1, 8)]
        S.profili = [profilo(i, f"{i}/foto_{n}.jpg") for n, i in enumerate(ids)]
        S.scartate = {f"{ids[2]}/foto_2.jpg": "x", f"{ids[5]}/foto_5.jpg": "y"}
        S.righe_per_pagina = 3  # il server dà meno righe di quelle chieste: si continua lo stesso
        attesa = ritaglia.Supabase(self.url, CHIAVE).in_attesa()
        self.assertEqual([i for i, _ in attesa], [ids[0], ids[1], ids[3], ids[4], ids[6]])

    def test_righe_che_spariscono_tra_una_pagina_e_l_altra(self):
        S = SupabaseFinto
        ids = [f"{i:08d}-0000-4000-8000-000000000000" for i in range(1, 6)]
        S.profili = [profilo(i, f"{i}/foto_{n}.jpg") for n, i in enumerate(ids)]
        S.righe_per_pagina = 2

        def spariscono():  # dopo la prima pagina tre membri tolgono la foto
            del S.profili[2:]
            S.dopo_pagina = None
        S.dopo_pagina = spariscono
        attesa = ritaglia.Supabase(self.url, CHIAVE).in_attesa()  # la pagina dopo non c'è più (416)
        self.assertEqual([i for i, _ in attesa], ids[:2])

    def test_conta_stampa_solo_il_numero(self):
        SupabaseFinto.profili.append(profilo(BRUNO, f"{BRUNO}/foto_1700000000100.jpg"))
        self.assertEqual(self.lancia("--conta"), 0)
        self.assertEqual(self.righe, ["2"])
        self.assertEqual(self.modello.chiamate, 0)
        self.assertEqual(self.metodi(), {"GET"})

    def test_conta_senza_librerie_pesanti(self):
        # Il passo "quante foto" del workflow gira prima di installare numpy, Pillow e rembg.
        cartella = str(Path(ritaglia.__file__).parent)
        codice = (
            "import sys; sys.path.insert(0, sys.argv[1]); import ritaglia\n"
            "env = {'SUPABASE_URL': sys.argv[2], 'SUPABASE_SECRET_KEY': sys.argv[3]}\n"
            "esiti = [ritaglia.main(['--conta'], env), ritaglia.main(['--modello'], env)]\n"
            "pesanti = [m for m in ('numpy', 'PIL', 'rembg', 'onnxruntime') if m in sys.modules]\n"
            "sys.exit(1 if any(esiti) or pesanti else 0)\n")
        esito = subprocess.run([sys.executable, "-c", codice, cartella, self.url, CHIAVE],
                               capture_output=True, text=True, timeout=60)
        self.assertEqual((esito.returncode, esito.stdout.split()), (0, ["1", ritaglia.MODELLO]), esito.stderr)

    def test_niente_da_fare_non_carica_il_modello(self):
        SupabaseFinto.profili[0]["avatar_cutout_path"] = f"{ANNA}/ritaglio_1.webp"
        self.assertEqual(self.lancia(), 0)
        self.assertEqual(self.righe, ["Nessuna foto da ritagliare."])
        self.assertEqual(self.modello.chiamate, 0)


# ----------------------------------------------------------------------------- giro completo

class FlussoTest(ConSupabaseFinto):
    def test_ritaglio_riuscito_e_pulizia(self):
        S = SupabaseFinto
        S.profili.append(profilo(BRUNO, f"{BRUNO}/foto_5.jpg", ritaglio=f"{BRUNO}/ritaglio_6.webp"))
        S.file.update({f"{ANNA}/ritaglio_1600000000000.webp": b"vecchio",
                       f"{ANNA}/ritaglio_1650000000000.webp": b"vecchio",
                       f"{BRUNO}/foto_5.jpg": FOTO, f"{BRUNO}/ritaglio_6.webp": b"di bruno"})
        self.assertEqual(self.lancia(), 0)
        nuovi = self.ritagli(ANNA)
        self.assertEqual(len(nuovi), 1)  # i ritagli vecchi di Anna sono stati tolti
        self.assertRegex(nuovi[0], rf"^{ANNA}/ritaglio_\d{{13}}\.webp$")
        self.assertEqual(S.profili[0]["avatar_cutout_path"], nuovi[0])
        self.assertEqual(S.tipi[nuovi[0]], "image/webp")
        self.assertEqual(apri_webp(S.file[nuovi[0]]).shape, (450, 360, 4))  # la stessa tela della foto
        # La foto resta, e la cartella di un altro membro non si tocca.
        self.assertIn(f"{ANNA}/foto_1700000000200.jpg", S.file)
        self.assertEqual(S.file[f"{BRUNO}/ritaglio_6.webp"], b"di bruno")
        self.assertEqual(self.righe[0], "1 foto da ritagliare")
        self.assertRegex(self.righe[1], r"^1 foto lavorata in \d+ secondi: 1 riuscita, 0 scartate$")
        self.senza_dati_personali()
        # Alla prossima esecuzione non c'è più niente da fare.
        self.righe.clear()
        self.assertEqual(self.lancia("--conta"), 0)
        self.assertEqual(self.righe, ["0"])

    def test_foto_cambiata_nel_frattempo(self):
        S = SupabaseFinto

        def cambia(percorso):  # mentre si lavora, il membro carica un'altra foto
            S.profili[0]["avatar_path"] = f"{ANNA}/foto_1700000009999.jpg"
        S.al_download = cambia
        self.assertEqual(self.lancia(), 0)
        self.assertIsNone(S.profili[0]["avatar_cutout_path"])
        self.assertEqual(self.ritagli(ANNA), [])   # il file appena caricato è stato cancellato
        self.assertEqual(S.scartate, {})           # e la foto vecchia non è uno scarto
        self.assertIn("1 cambiata nel frattempo", self.righe[-1])
        self.senza_dati_personali()

    def test_ritaglio_gia_presente_non_si_sovrascrive(self):
        S = SupabaseFinto

        def altro_worker(percorso):  # un'altra esecuzione arriva prima
            S.profili[0]["avatar_cutout_path"] = f"{ANNA}/ritaglio_1.webp"
            S.file[f"{ANNA}/ritaglio_1.webp"] = b"dell'altro"
        S.al_download = altro_worker
        self.assertEqual(self.lancia(), 0)
        self.assertEqual(S.profili[0]["avatar_cutout_path"], f"{ANNA}/ritaglio_1.webp")
        self.assertEqual(self.ritagli(ANNA), [f"{ANNA}/ritaglio_1.webp"])

    def test_scarto_registrato_e_non_riprovato(self):
        S = SupabaseFinto
        modello = ModelloFinto(lambda foto: Image.new("L", foto.size, 255))
        self.assertEqual(self.lancia(modello=modello), 0)
        self.assertEqual(list(S.scartate), [f"{ANNA}/foto_1700000000200.jpg"])
        self.assertIn("sfondo non separato", S.scartate[f"{ANNA}/foto_1700000000200.jpg"])
        self.assertEqual(self.ritagli(ANNA), [])
        self.assertIsNone(S.profili[0]["avatar_cutout_path"])
        self.assertRegex(self.righe[-1], r"0 riuscite, 1 scartata$")
        self.senza_dati_personali()
        self.righe.clear()
        self.assertEqual(self.lancia(modello=modello), 0)
        self.assertEqual(self.righe, ["Nessuna foto da ritagliare."])
        self.assertEqual(modello.chiamate, 1)

    def test_file_illeggibile_o_mancante_sono_scarti(self):
        S = SupabaseFinto
        S.profili.append(profilo(BRUNO, f"{BRUNO}/foto_1700000000300.jpg"))
        S.file[f"{ANNA}/foto_1700000000200.jpg"] = b"non sono una foto"
        self.assertEqual(self.lancia(), 0)
        self.assertEqual(S.scartate, {f"{ANNA}/foto_1700000000200.jpg": "immagine non leggibile",
                                      f"{BRUNO}/foto_1700000000300.jpg": "file della foto non trovato"})
        self.assertRegex(self.righe[-1], r"0 riuscite, 2 scartate$")
        self.senza_dati_personali()

    def test_errore_di_rete_non_e_uno_scarto(self):
        S = SupabaseFinto
        for operazione, cosa in (("scarica", "download della foto"), ("carica", "caricamento del ritaglio"),
                                 ("assegna", "aggiornamento del profilo")):
            with self.subTest(operazione):
                self.setUp()
                S.guasti = {operazione: 503}
                self.assertEqual(self.lancia(GITHUB_ACTIONS="true"), 1)   # il workflow diventa rosso
                self.assertEqual(S.scartate, {})     # ma la foto si riprova alla prossima esecuzione
                self.assertIsNone(S.profili[0]["avatar_cutout_path"])
                self.assertEqual(self.ritagli(ANNA), [])  # nessun file lasciato a metà
                self.assertIn("1 rimandata per un errore di rete", self.righe[-1])
                # Nei log si dice che cosa non ha funzionato: operazione, codice e sigla, nient'altro.
                self.assertEqual(self.avvisi, [f"::error::{cosa}: errore 503 XX000 (1 foto)"])
                self.senza_dati_personali()

    def test_scarto_non_registrabile_si_riprova(self):
        S = SupabaseFinto
        S.guasti = {"scarta": 500}
        self.assertEqual(self.lancia(modello=ModelloFinto(lambda foto: Image.new("L", foto.size, 0))), 1)
        self.assertEqual(S.scartate, {})
        self.assertIn("1 rimandata", self.righe[-1])

    def test_pulizia_fallita_non_rovina_il_ritaglio(self):
        S = SupabaseFinto
        S.file[f"{ANNA}/ritaglio_1600000000000.webp"] = b"vecchio"
        S.guasti = {"elenca": 500}
        self.assertEqual(self.lancia(), 0)
        self.assertEqual(len(self.ritagli(ANNA)), 2)  # il vecchio resta fino alla prossima foto
        self.assertIn(S.profili[0]["avatar_cutout_path"], self.ritagli(ANNA))

    def test_troppi_errori_di_fila_ci_si_ferma(self):
        S = SupabaseFinto
        ids = [f"{i:08d}-0000-4000-8000-000000000000" for i in range(1, 7)]
        S.profili = [profilo(i, f"{i}/foto_{n}.jpg") for n, i in enumerate(ids)]
        S.guasti = {"scarica": 500}
        self.assertEqual(self.lancia(), 1)
        self.assertIn("3 rimandate per errori di rete, 3 rimaste per la prossima esecuzione", self.righe[-1])
        self.assertEqual(self.modello.chiamate, 0)

    def test_prova_non_scrive_nulla(self):
        S = SupabaseFinto
        S.profili.append(profilo(BRUNO, f"{BRUNO}/foto_1700000000300.jpg"))
        S.file[f"{BRUNO}/foto_1700000000300.jpg"] = b"non sono una foto"
        S.file[f"{ANNA}/ritaglio_1600000000000.webp"] = b"vecchio"
        prima = (json.dumps(S.profili), dict(S.file))
        self.assertEqual(self.lancia(DRY_RUN="1"), 0)
        self.assertEqual(self.metodi(), {"GET"})   # nessun caricamento, modifica o cancellazione
        self.assertEqual((json.dumps(S.profili), S.file, S.scartate), (*prima, {}))
        self.assertEqual(self.modello.chiamate, 1)  # ma il ritaglio si prova davvero
        self.assertRegex(self.righe[-1], r"1 riuscita, 1 scartata \(prova: nulla salvato\)$")
        self.senza_dati_personali()

    def test_massimo_per_esecuzione(self):
        S = SupabaseFinto
        for n, id_ in enumerate((BRUNO, CARLA)):
            S.profili.append(profilo(id_, f"{id_}/foto_170000000030{n}.jpg"))
            S.file[f"{id_}/foto_170000000030{n}.jpg"] = FOTO
        self.assertEqual(self.lancia(MAX_FOTO="2"), 0)
        self.assertEqual(self.righe[0], "3 foto da ritagliare (al massimo 2 per esecuzione)")
        self.assertRegex(self.righe[-1],
                         r"^2 foto lavorate .* 2 riuscite, 0 scartate, 1 rimasta per la prossima esecuzione$")
        self.assertEqual([bool(p["avatar_cutout_path"]) for p in S.profili], [True, True, False])  # dalla più vecchia

    def test_tempo_massimo(self):
        S = SupabaseFinto
        S.profili.append(profilo(BRUNO, f"{BRUNO}/foto_1700000000300.jpg"))
        S.file[f"{BRUNO}/foto_1700000000300.jpg"] = FOTO
        orologio = iter(range(0, 100000, 1000))  # ogni lettura dell'orologio vale 1000 secondi
        esito = ritaglia.lavora(ritaglia.Supabase(self.url, CHIAVE), ModelloFinto(), stampa=self.righe.append,
                                orologio=lambda: next(orologio))
        self.assertEqual(esito, 0)
        self.assertIn("2 rimaste per la prossima esecuzione", self.righe[-1])

    def test_modello_guasto_non_scarta_le_foto(self):
        S = SupabaseFinto
        S.profili.append(profilo(BRUNO, f"{BRUNO}/foto_1700000000300.jpg"))
        S.file[f"{BRUNO}/foto_1700000000300.jpg"] = FOTO
        self.assertEqual(self.lancia(modello=ModelloFinto(guasto=True)), 1)
        self.assertEqual(S.scartate, {})   # il guasto è del modello, non delle foto
        self.assertEqual(self.avvisi, ["Il modello non funziona (RuntimeError): mi fermo, "
                                       "nessuna foto viene scartata per questo"])
        self.assertIn("2 rimaste per la prossima esecuzione", self.righe[-1])
        self.senza_dati_personali()

    def test_errore_su_una_sola_foto_e_uno_scarto(self):
        S = SupabaseFinto
        S.profili.append(profilo(BRUNO, f"{BRUNO}/foto_1700000000300.jpg"))
        S.file[f"{BRUNO}/foto_1700000000300.jpg"] = FOTO
        chiamate = []

        def capricciosa(foto):
            chiamate.append(foto.size)
            if len(chiamate) == 1:
                raise ValueError(f"dettaglio da non scrivere: {ANNA}")
            return ovale(foto.size)
        self.assertEqual(self.lancia(modello=ModelloFinto(capricciosa)), 0)
        self.assertEqual(S.scartate, {f"{ANNA}/foto_1700000000200.jpg": "errore durante il ritaglio (ValueError)"})
        self.assertTrue(S.profili[1]["avatar_cutout_path"])
        self.assertRegex(self.righe[-1], r"1 riuscita, 1 scartata$")
        self.senza_dati_personali()


# ----------------------------------------------------------------------------- errori e chiavi

class ErroriTest(ConSupabaseFinto):
    def test_chiave_mancante(self):
        for env in ({"SUPABASE_SECRET_KEY": ""}, {"SUPABASE_URL": ""}):
            for argomenti in ((), ("--conta",)):
                self.assertEqual(self.lancia(*argomenti, **env), 1)
        self.assertEqual(set(self.avvisi), {"SUPABASE_URL o SUPABASE_SECRET_KEY mancanti"})
        self.assertEqual((self.righe, SupabaseFinto.richieste), ([], []))
        self.avvisi.clear()
        self.lancia("--conta", SUPABASE_SECRET_KEY="", GITHUB_ACTIONS="true")
        self.assertEqual(self.avvisi, ["::error::SUPABASE_URL o SUPABASE_SECRET_KEY mancanti"])

    def test_chiave_sbagliata(self):
        self.assertEqual(self.lancia("--conta", SUPABASE_SECRET_KEY="sb_secret_altra"), 1)
        self.assertEqual(self.avvisi, ["elenco dei profili: errore 401"])
        self.assertEqual(self.righe, [])
        self.senza_dati_personali()

    def test_supabase_irraggiungibile(self):
        self.assertEqual(self.lancia(SUPABASE_URL="http://127.0.0.1:9"), 1)
        self.assertEqual(self.avvisi, ["elenco dei profili: Supabase non raggiungibile"])

    def test_errore_del_server_senza_dettagli(self):
        # Il messaggio di Supabase può contenere percorsi: nei log va solo codice e sigla.
        SupabaseFinto.guasti = {"leggi": 500}
        self.assertEqual(self.lancia("--conta"), 1)
        self.assertEqual(self.avvisi, ["elenco dei profili: errore 500 XX000"])
        self.assertEqual(sum(1 for r in SupabaseFinto.richieste if r[0] == "GET"), 2)  # un secondo tentativo

    def test_database_non_ancora_aggiornato(self):
        SupabaseFinto.senza_migrazione = True
        for argomenti, righe in ((("--conta",), ["0"]), ((), [])):
            self.righe.clear()
            self.avvisi.clear()
            self.assertEqual(self.lancia(*argomenti, GITHUB_ACTIONS="true"), 0)
            self.assertEqual(self.righe, righe)
            self.assertEqual(len(self.avvisi), 1)
            self.assertTrue(self.avvisi[0].startswith("::warning::Il database non ha ancora"))

    def test_intestazioni(self):
        # Le chiavi sb_secret_ vanno solo in apikey e vengono rifiutate (401) con un User-Agent da browser.
        nuova = ritaglia.Supabase("https://x.supabase.co/", "sb_secret_test")
        self.assertEqual(nuova.base, "https://x.supabase.co")
        self.assertEqual(nuova.intestazioni["apikey"], "sb_secret_test")
        self.assertNotIn("Authorization", nuova.intestazioni)
        self.assertNotIn("mozilla", nuova.intestazioni["User-Agent"].lower())
        vecchia = ritaglia.Supabase("https://x.supabase.co", "eyJhbGciOi.vecchia.chiave")
        self.assertEqual(vecchia.intestazioni["Authorization"], "Bearer eyJhbGciOi.vecchia.chiave")
        self.lancia()
        self.assertTrue(all(i.get("User-Agent") == ritaglia.USER_AGENT for i in SupabaseFinto.intestazioni_viste))

    def test_argomenti_sbagliati(self):
        self.assertEqual(self.lancia("--altro"), 2)
        self.assertEqual(SupabaseFinto.richieste, [])


class FileLocaleTest(unittest.TestCase):
    def test_ritaglia_un_file(self):
        import tempfile

        with tempfile.TemporaryDirectory() as cartella:
            origine, destinazione = Path(cartella) / "foto.jpg", Path(cartella) / "ritaglio.webp"
            origine.write_bytes(FOTO)
            righe: list[str] = []
            esito = ritaglia.main(["--file", str(origine), str(destinazione)], {}, stampa=righe.append,
                                  ritagliatore=ModelloFinto())
            self.assertEqual(esito, 0)
            self.assertEqual(apri_webp(destinazione.read_bytes()).shape, (450, 360, 4))
            self.assertRegex(righe[0], r"^Ritaglio salvato: \d+ kB$")
            # Una foto che non passa il controllo non lascia file.
            destinazione.unlink()
            vuoto = ModelloFinto(lambda foto: Image.new("L", foto.size, 0))
            self.assertEqual(ritaglia.main(["--file", str(origine), str(destinazione)], {}, stampa=righe.append,
                                           ritagliatore=vuoto), 1)
            self.assertFalse(destinazione.exists())
            self.assertIn("Foto scartata: soggetto non trovato", righe[-1])


if __name__ == "__main__":
    unittest.main()
