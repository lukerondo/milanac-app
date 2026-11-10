#!/usr/bin/env python3
"""Ritaglia dallo sfondo le foto dei membri, per le carte dell'app MILANAC.

Eseguito da GitHub Actions ogni 15 minuti (workflow "Ritagli"). Cerca i profili attivi con una
foto ancora senza ritaglio, toglie lo sfondo con un modello open source (rembg), carica il
risultato (WebP trasparente, stessa inquadratura della foto) nel bucket privato "avatars" e ne
salva il percorso in profiles.avatar_cutout_path. Le foto che non si riescono a ritagliare bene
finiscono in cutout_failures e non si riprovano: sulla carta resta la foto intera.

Uso:
  ritaglia.py                            ritaglia le foto in attesa
  ritaglia.py --conta                    stampa solo quante sono (libreria standard, niente modello)
  ritaglia.py --modello                  stampa il nome del modello (chiave della cache del workflow)
  ritaglia.py --file foto.jpg out.webp   ritaglia un file in locale

Variabili d'ambiente:
  SUPABASE_URL          es. https://xxxx.supabase.co
  SUPABASE_SECRET_KEY   chiave segreta (sb_secret_...), salvata nei Secrets di GitHub
  DRY_RUN=1             prova: scarica e ritaglia, ma non carica, non aggiorna e non cancella nulla
  MAX_FOTO              foto per esecuzione (predefinito 20)

I log di GitHub Actions sono pubblici: si stampano solo numeri, mai id, nomi o percorsi.
numpy, Pillow e rembg si importano solo quando c'è almeno una foto da lavorare.
"""
from __future__ import annotations

import http.client
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Callable

# Modello di rembg (pesi con licenza MIT). Tra quelli provati è quello che segue meglio capelli
# e spalle nei ritratti; con 4 CPU impiega circa 20 secondi a foto e 8 GB di memoria.
MODELLO = "birefnet-portrait"
BUCKET = "avatars"
# Come per le notizie: niente User-Agent da browser, le chiavi sb_secret_ verrebbero rifiutate (401).
USER_AGENT = "milanac-ritaglio-foto/1.0 (+https://github.com/lukerondo/milanac-app)"

LATO_MAX = 1000                 # lato lungo del ritaglio; le foto più piccole non si ingrandiscono
LATO_MIN = 64                   # sotto, non è una foto da carta
PUNTI_MAX = 40_000_000          # foto più grandi non si aprono nemmeno (memoria)
QUALITA_WEBP = 90
PESO_MAX = 5 * 1024 * 1024      # limite del bucket
MAX_FOTO = 20                   # per esecuzione
MINUTI_MAX = 15                 # oltre, le foto rimaste aspettano la prossima esecuzione
ERRORI_DI_FILA = 3              # errori di rete consecutivi dopo i quali ci si ferma
PAGINA = 1000                   # righe per richiesta
GRUPPO = 40                     # percorsi per ogni controllo in cutout_failures
TEMPO_RETE = 60                 # secondi
PAUSA = 3                       # secondi prima di riprovare una lettura
RISPOSTA_MAX = 20 * 1024 * 1024

# Rifinitura dell'opacità (valori da 0 a 1).
OPACITA_BASSA = 0.06            # sotto è sfondo: via la velatura attorno al soggetto
OPACITA_ALTA = 0.96             # sopra è soggetto pieno
ISOLA_MIN = 0.04                # macchie staccate più piccole del 4% del soggetto: tolte

# Controllo di qualità: se uno di questi numeri è fuori posto la foto si scarta (sulla carta
# resta intera). Soglie tarate su 12 ritratti veri e una ventina di foto "sbagliate".
#  - quota tenuta: i mezzi busti in 4:5 tengono tra il 43% e il 68% dell'immagine. Sotto l'8%
#    il soggetto non c'è o è troppo lontano per una carta (tinta unita e folla lontana danno
#    0%); sopra il 93% non c'è sfondo da togliere (un viso che riempie la foto arriva al 92%
#    e passa, una foto senza sfondo dà 100%).
#  - bordo incerto: quota del soggetto con opacità a metà. Nei ritratti va dall'1% all'8%
#    (capelli ricci al vento); oltre il 25% il modello non sa dov'è il contorno e il ritaglio
#    verrebbe a chiazze o velato.
#  - isole: opacità finita in macchie staccate dal soggetto (e tolte). Nei ritratti è zero;
#    oltre il 15% il soggetto è a pezzi.
TENUTA_MIN = 0.08
TENUTA_MAX = 0.93
INCERTA_MAX = 0.25
ISOLE_MAX = 0.15

_UUID = re.compile(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")
_NOME_FILE = re.compile(r"[A-Za-z0-9._-]{1,120}")


class Scartata(Exception):
    """La foto non si può ritagliare bene. Il motivo (breve, senza dati personali) va in cutout_failures."""


class ErroreSupabase(Exception):
    """Rete o Supabase: non dipende dalla foto, si riprova alla prossima esecuzione."""

    def __init__(self, testo: str, codice: int = 0, sigla: str = "", stato: str = ""):
        super().__init__(testo)
        self.codice, self.sigla, self.stato = codice, sigla, stato


class DatabaseNonAggiornato(ErroreSupabase):
    """Mancano la colonna o la tabella dei ritagli: la migrazione non è ancora applicata."""


class FotoMancante(Exception):
    """Il profilo punta a un file che nel bucket non c'è più."""


class ModelloGuasto(Exception):
    """Il modello non parte o non funziona: non è colpa delle foto, ci si ferma."""


# ----------------------------------------------------------------------------- immagine

def apri(dati: bytes):
    """La foto pronta da ritagliare: dritta (orientamento EXIF), RGB, lato lungo al massimo LATO_MAX."""
    from PIL import Image, ImageOps

    try:
        foto = Image.open(io.BytesIO(dati))
        if foto.width * foto.height > PUNTI_MAX:
            raise Scartata("immagine troppo grande")
        profilo = foto.info.get("icc_profile")
        if max(foto.size) > LATO_MAX:
            foto.thumbnail((LATO_MAX, LATO_MAX), Image.Resampling.LANCZOS)
        foto = ImageOps.exif_transpose(foto)
        if "A" in foto.getbands() or "transparency" in foto.info:
            # PNG o WebP già trasparenti: su bianco, come li mostrerebbe l'app.
            foto = foto.convert("RGBA")
            foto = Image.alpha_composite(Image.new("RGBA", foto.size, "white"), foto)
        foto = foto.convert("RGB")
        # Il profilo colore, se c'è, passa al ritaglio: stessi colori della foto.
        foto.info = {"icc_profile": profilo} if profilo else {}
    except Scartata:
        raise
    except Exception:  # noqa: BLE001 - qualunque file che Pillow non legge
        raise Scartata("immagine non leggibile") from None
    if min(foto.size) < LATO_MIN:
        raise Scartata("immagine troppo piccola")
    return foto


def _vicini(bordata):
    """I quattro vicini (su, giù, sinistra, destra) di una matrice già bordata di un punto."""
    return bordata[:-2, 1:-1], bordata[2:, 1:-1], bordata[1:-1, :-2], bordata[1:-1, 2:]


def _pezzi(pieno):
    """Numera i pezzi connessi di una griglia booleana: ogni pezzo prende l'indice più alto
    dei suoi punti, propagando il massimo tra vicini finché non cambia più nulla."""
    import numpy as np

    etichette = np.where(pieno, np.arange(1, pieno.size + 1, dtype=np.int32).reshape(pieno.shape), 0)
    for _ in range(4 * sum(pieno.shape)):
        nuove = np.where(pieno, np.maximum.reduce((etichette,) + _vicini(np.pad(etichette, 1))), 0)
        if np.array_equal(nuove, etichette):
            break
        etichette = nuove
    return etichette


def togli_isole(alpha, passo: int = 4):
    """Azzera le macchie staccate dal soggetto (leggere rispetto al pezzo più pesante).
    Restituisce l'opacità ripulita e la quota di opacità tolta."""
    import numpy as np

    h, w = alpha.shape
    hh, ww = -(-h // passo), -(-w // passo)
    tela = np.zeros((hh * passo, ww * passo), dtype=alpha.dtype)
    tela[:h, :w] = alpha
    riquadri = tela.reshape(hh, passo, ww, passo)
    # Griglia ridotta: un riquadro conta se ha anche un solo punto visibile, così i fili
    # sottili e i bordi morbidi restano attaccati al loro pezzo.
    pieno = riquadri.max(axis=(1, 3)) > 0.02
    etichette = _pezzi(pieno)
    valori, quale = np.unique(etichette[pieno], return_inverse=True)
    if len(valori) <= 1:
        return alpha, 0.0
    pesi = np.bincount(quale, weights=riquadri.sum(axis=(1, 3))[pieno])
    buoni = np.isin(etichette, valori[pesi >= ISOLA_MIN * pesi.max()])
    buoni = np.repeat(np.repeat(buoni, passo, axis=0), passo, axis=1)[:h, :w]
    tolta = float(alpha[~buoni].sum() / max(float(alpha.sum()), 1e-6))
    return np.where(buoni, alpha, 0).astype(alpha.dtype), tolta


def rifinisci(maschera):
    """Dalla maschera del modello (0-255) all'opacità finale (0-1), più la quota di isole tolte.

    Il bordo resta morbido: si tolgono solo la velatura sullo sfondo e le macchie staccate,
    poi una sfumatura leggerissima (3x3, circa 0,7 punti) leva la scalettatura.
    """
    import numpy as np

    alpha = np.asarray(maschera, dtype=np.float32) / 255
    alpha = np.clip((alpha - OPACITA_BASSA) / (OPACITA_ALTA - OPACITA_BASSA), 0, 1)
    alpha, tolta = togli_isole(alpha)
    b = np.pad(alpha, 1, mode="edge")
    sfumata = (b[:, :-2] + 2 * b[:, 1:-1] + b[:, 2:]) / 4
    sfumata = (sfumata[:-2] + 2 * sfumata[1:-1] + sfumata[2:]) / 4
    return np.clip(sfumata, 0, 1).astype(np.float32), tolta


def controlla(alpha, isole: float = 0.0) -> None:
    """Controllo di qualità (vedi le soglie in cima): alza Scartata con il motivo."""
    tenuta = float(alpha.mean())
    if tenuta < TENUTA_MIN:
        raise Scartata(f"soggetto non trovato (resta il {tenuta:.0%} dell'immagine)")
    if tenuta > TENUTA_MAX:
        raise Scartata(f"sfondo non separato (resta il {tenuta:.0%} dell'immagine)")
    soggetto = int((alpha > 0.1).sum())
    incerta = float(((alpha > 0.1) & (alpha < 0.9)).sum() / max(soggetto, 1))
    if incerta > INCERTA_MAX:
        raise Scartata(f"contorno incerto ({incerta:.0%} del soggetto)")
    if isole > ISOLE_MAX:
        raise Scartata(f"soggetto a pezzi ({isole:.0%} in macchie staccate)")


def stima_primo_piano(foto, alpha, giri_piccoli: int = 10, giri_grandi: int = 4):
    """Il colore vero del soggetto nei punti semitrasparenti, senza quello del vecchio sfondo.

    Ogni punto della foto è un misto I = a*F + (1-a)*B: si cercano F (soggetto) e B (sfondo)
    lisci dove l'opacità non cambia, dall'immagine più piccola alla più grande (stima
    multilivello di Germer e altri, 2020, la stessa di pymatting; qui in numpy, aggiornando
    tutti i punti insieme). foto e alpha sono matrici float tra 0 e 1.
    """
    import numpy as np

    h0, w0 = alpha.shape
    davanti, dietro = alpha > 0.9, alpha < 0.1
    F = (foto[davanti].sum(0) / (davanti.sum() + 1e-5)).reshape(1, 1, 3).astype(np.float32)
    B = (foto[dietro].sum(0) / (dietro.sum() + 1e-5)).reshape(1, 1, 3).astype(np.float32)
    livelli = max(1, int(np.ceil(np.log2(max(w0, h0)))))
    bordo = ((1, 1), (1, 1), (0, 0))
    for livello in range(livelli + 1):
        w, h = round(w0 ** (livello / livelli)), round(h0 ** (livello / livelli))
        righe = np.minimum(h0 - 1, np.arange(h) * h0 // h)[:, None]
        colonne = np.minimum(w0 - 1, np.arange(w) * w0 // w)[None, :]
        img, a = foto[righe, colonne], alpha[righe, colonne]
        righe = np.minimum(F.shape[0] - 1, np.arange(h) * F.shape[0] // h)[:, None]
        colonne = np.minimum(F.shape[1] - 1, np.arange(w) * F.shape[1] // w)[None, :]
        F, B = F[righe, colonne], B[righe, colonne]

        # Peso di ogni vicino: quasi zero dove l'opacità cambia poco, alto sul bordo.
        pesi = [(1e-5 + np.abs(a - v))[..., None] for v in _vicini(np.pad(a, 1, mode="edge"))]
        somma = pesi[0] + pesi[1] + pesi[2] + pesi[3]
        a0 = a[..., None]
        a1 = 1.0 - a0
        a00, a01, a11 = a0 * a0 + somma, a0 * a1, a1 * a1 + somma
        inverso = 1.0 / (a00 * a11 - a01 * a01)
        for _ in range(giri_piccoli if max(w, h) <= 32 else giri_grandi):
            b0, b1 = a0 * img, a1 * img
            for peso, Fv, Bv in zip(pesi, _vicini(np.pad(F, bordo, mode="edge")),
                                    _vicini(np.pad(B, bordo, mode="edge"))):
                b0 += peso * Fv
                b1 += peso * Bv
            F = np.clip(inverso * (a11 * b0 - a01 * b1), 0, 1)
            B = np.clip(inverso * (a00 * b1 - a01 * b0), 0, 1)
    return F


def componi(foto, maschera) -> bytes:
    """Foto RGB e maschera del modello -> WebP trasparente, stessa tela e stessa inquadratura."""
    import numpy as np
    from PIL import Image

    if maschera.size != foto.size:
        maschera = maschera.resize(foto.size, Image.Resampling.BILINEAR)
    alpha, isole = rifinisci(np.asarray(maschera.convert("L")))
    controlla(alpha, isole)
    rgb = np.asarray(foto.convert("RGB"), dtype=np.float32) / 255
    colore = stima_primo_piano(rgb, alpha)
    # Dove il soggetto è pieno resta il colore della foto, punto per punto.
    colore = np.where(alpha[..., None] >= 0.999, rgb, colore)
    rgba = np.round(np.dstack([colore, alpha]) * 255).astype(np.uint8)
    dati = io.BytesIO()
    # Colori con perdita (qualità 90), opacità senza perdita: un ritaglio 720x900 pesa sugli 80 kB.
    Image.fromarray(rgba).save(dati, "WEBP", quality=QUALITA_WEBP,
                               icc_profile=foto.info.get("icc_profile"))
    if dati.tell() > PESO_MAX:
        raise Scartata("ritaglio troppo pesante")
    return dati.getvalue()


class Ritagliatore:
    """Il modello, caricato alla prima foto e tenuto in memoria per le successive."""

    def __init__(self, modello: str = MODELLO):
        self.modello = modello
        self._sessione = None
        self._funziona: bool | None = None

    def maschera(self, foto):
        """La maschera del soggetto (immagine in scala di grigi, grande come la foto)."""
        if self._sessione is None:
            # onnxruntime di suo manda dati d'uso a Microsoft e salva un identificativo della
            # macchina: qui non serve. Va spento prima di importarlo.
            os.environ.setdefault("ORT_DISABLE_TELEMETRY", "1")
            try:
                import onnxruntime as ort
                from rembg import new_session

                opzioni = ort.SessionOptions()
                # Senza queste due opzioni onnxruntime tiene da parte la memoria di ogni foto:
                # con questo modello si superano i 14 GB alla seconda (il runner ne ha 16).
                opzioni.enable_mem_pattern = False
                opzioni.enable_cpu_mem_arena = False
                self._sessione = new_session(self.modello, sess_opts=opzioni)
            except Exception as e:  # noqa: BLE001 - dipendenze o modello non scaricabile
                raise ModelloGuasto(type(e).__name__) from None
        return self._sessione.predict(foto)[0]

    def funziona(self) -> bool:
        """Prova il modello su un'immagine disegnata: distingue una foto difettosa da un guasto
        generale (che non deve riempire cutout_failures). Si prova una volta sola."""
        if self._funziona is None:
            try:
                from PIL import Image

                self.maschera(Image.linear_gradient("L").resize((160, 200)).convert("RGB"))
                self._funziona = True
            except Exception:  # noqa: BLE001
                self._funziona = False
        return self._funziona

    def ritaglia(self, dati: bytes) -> bytes:
        """Dal file caricato dal membro al WebP ritagliato. Alza Scartata se non viene bene."""
        foto = apri(dati)
        return componi(foto, self.maschera(foto))


# ----------------------------------------------------------------------------- Supabase

def foto_valida(id_: str, percorso) -> bool:
    """Il percorso sta nella cartella del membro e ha un nome semplice, come quelli dell'app
    (<id>/foto_<ms>.jpg). Il campo è testo libero: tutto il resto si ignora."""
    if not isinstance(percorso, str) or not _UUID.fullmatch(id_) or not percorso.startswith(id_ + "/"):
        return False
    nome = percorso[len(id_) + 1:]
    return bool(_NOME_FILE.fullmatch(nome)) and ".." not in nome


def _caricata_il(percorso: str) -> int:
    """I millisecondi nel nome del file (foto_<ms>.jpg): servono a partire dalla più vecchia."""
    trovato = re.search(r"/foto_(\d{1,18})\.", percorso)
    return int(trovato.group(1)) if trovato else 10 ** 18


class Supabase:
    """Le poche chiamate che servono, con la chiave segreta: tabelle (PostgREST) e Storage."""

    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/")
        self.intestazioni = {"apikey": key, "User-Agent": USER_AGENT}
        if not key.startswith("sb_"):  # vecchia chiave service_role (JWT)
            self.intestazioni["Authorization"] = f"Bearer {key}"

    def _chiama(self, metodo: str, percorso: str, cosa: str, *, corpo: bytes | None = None,
                intestazioni: dict | None = None, tentativi: int = 1):
        """Una richiesta. Negli errori restano solo il codice HTTP e la sigla dell'errore:
        il messaggio di Supabase può contenere percorsi (i log sono pubblici)."""
        for tentativo in range(1, tentativi + 1):
            try:
                req = urllib.request.Request(self.base + percorso, data=corpo, method=metodo,
                                             headers={**self.intestazioni, **(intestazioni or {})})
                with urllib.request.urlopen(req, timeout=TEMPO_RETE) as risposta:
                    return risposta.read(RISPOSTA_MAX), risposta.headers
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 504) and tentativo < tentativi:
                    time.sleep(PAUSA)
                    continue
                try:
                    dati = json.loads(e.read().decode(errors="replace"))
                except (ValueError, OSError):
                    dati = {}
                dati = dati if isinstance(dati, dict) else {}
                sigla = re.sub(r"[^A-Za-z0-9_ ]", "", str(dati.get("code") or dati.get("error") or ""))[:40]
                classe = DatabaseNonAggiornato if sigla in ("42703", "42P01", "PGRST204", "PGRST205") \
                    else ErroreSupabase
                raise classe(f"{cosa}: errore {e.code} {sigla}".rstrip(), e.code, sigla,
                             str(dati.get("statusCode") or "")) from None
            except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
                if tentativo < tentativi:
                    time.sleep(PAUSA)
                    continue
                raise ErroreSupabase(f"{cosa}: Supabase non raggiungibile") from None
        raise ErroreSupabase(f"{cosa}: nessun tentativo")

    def _json(self, corpo: bytes, cosa: str):
        try:
            return json.loads(corpo or b"null")
        except ValueError:
            raise ErroreSupabase(f"{cosa}: risposta non valida") from None

    def _righe(self, tabella: str, filtri: str, cosa: str) -> list[dict]:
        """Tutte le righe, una pagina alla volta (il totale arriva in Content-Range)."""
        righe: list[dict] = []
        while True:
            try:
                corpo, intestazioni = self._chiama(
                    "GET", f"/rest/v1/{tabella}?{filtri}&limit={PAGINA}&offset={len(righe)}", cosa,
                    intestazioni={"Prefer": "count=exact"}, tentativi=2)
            except ErroreSupabase as e:
                if e.codice == 416 and righe:  # tra una pagina e l'altra le righe sono diminuite
                    return righe
                raise
            pagina = self._json(corpo, cosa)
            if not isinstance(pagina, list):
                raise ErroreSupabase(f"{cosa}: risposta non valida")
            righe += [r for r in pagina if isinstance(r, dict)]
            totale = (intestazioni.get("Content-Range") or "").rpartition("/")[2]
            finite = len(righe) >= int(totale) if totale.isdecimal() else len(pagina) < PAGINA
            if not pagina or finite:
                return righe

    def in_attesa(self) -> list[tuple[str, str]]:
        """Profili attivi con una foto senza ritaglio e non già scartata: (id, percorso della
        foto), a partire da quella caricata per prima."""
        profili = self._righe(
            "profiles",
            "select=id,avatar_path&active=is.true&avatar_path=not.is.null"
            "&avatar_cutout_path=is.null&order=id",
            "elenco dei profili")
        coppie = [(str(p.get("id")), p.get("avatar_path")) for p in profili]
        coppie = [c for c in coppie if foto_valida(*c)]
        scartate = self._scartate([percorso for _, percorso in coppie])
        return sorted((c for c in coppie if c[1] not in scartate),
                      key=lambda c: (_caricata_il(c[1]), c[1]))

    def _scartate(self, percorsi: list[str]) -> set[str]:
        """Quali di questi percorsi sono già in cutout_failures."""
        trovate: set[str] = set()
        for i in range(0, len(percorsi), GRUPPO):
            # Tra virgolette, come vuole PostgREST per i valori con punti e barre.
            elenco = ",".join('"' + p.replace("\\", "\\\\").replace('"', '\\"') + '"'
                              for p in percorsi[i:i + GRUPPO])
            filtri = ("select=avatar_path&order=avatar_path&avatar_path=in."
                      + urllib.parse.quote(f"({elenco})", safe=""))
            trovate |= {r.get("avatar_path") for r in
                        self._righe("cutout_failures", filtri, "registro delle foto scartate")}
        return trovate

    def scarica(self, percorso: str) -> bytes:
        try:
            corpo, _ = self._chiama("GET", f"/storage/v1/object/{BUCKET}/{urllib.parse.quote(percorso)}",
                                    "download della foto", tentativi=2)
        except ErroreSupabase as e:
            # Lo Storage risponde 400 o 404 con statusCode "404" se il file non c'è.
            if e.sigla in ("NoSuchKey", "not_found") or (e.stato == "404" and "ucket" not in e.sigla):
                raise FotoMancante() from None
            raise
        return corpo

    def carica(self, percorso: str, dati: bytes) -> None:
        self._chiama("POST", f"/storage/v1/object/{BUCKET}/{urllib.parse.quote(percorso)}",
                     "caricamento del ritaglio", corpo=dati,
                     intestazioni={"Content-Type": "image/webp", "Cache-Control": "max-age=31536000",
                                   "x-upsert": "false"})

    def assegna(self, id_: str, foto: str, ritaglio: str) -> bool:
        """Scrive il ritaglio nel profilo solo se la foto è ancora quella lavorata e un ritaglio
        non c'è già (il membro può averla cambiata nel frattempo). True se la riga è cambiata."""
        filtri = (f"id=eq.{id_}&avatar_path=eq.{urllib.parse.quote(foto, safe='')}"
                  "&avatar_cutout_path=is.null&select=id")
        corpo, _ = self._chiama("PATCH", f"/rest/v1/profiles?{filtri}", "aggiornamento del profilo",
                                corpo=json.dumps({"avatar_cutout_path": ritaglio}).encode(),
                                intestazioni={"Content-Type": "application/json",
                                              "Prefer": "return=representation"})
        return bool(self._json(corpo, "aggiornamento del profilo"))

    def ritaglio_di(self, id_: str) -> str | None:
        """Il ritaglio a cui punta ora il profilo."""
        righe = self._righe("profiles", f"select=avatar_cutout_path&id=eq.{id_}", "lettura del profilo")
        return righe[0].get("avatar_cutout_path") if righe else None

    def segna_scartata(self, foto: str, motivo: str) -> None:
        self._chiama("POST", "/rest/v1/cutout_failures?on_conflict=avatar_path",
                     "registro delle foto scartate",
                     corpo=json.dumps({"avatar_path": foto, "reason": motivo[:200]}).encode(),
                     intestazioni={"Content-Type": "application/json",
                                   "Prefer": "resolution=ignore-duplicates,return=minimal"})

    def altri_ritagli(self, id_: str, tieni: str) -> list[str]:
        """I ritagli nella cartella del membro, tranne quello da tenere."""
        cosa = "elenco dei ritagli"
        corpo, _ = self._chiama(
            "POST", f"/storage/v1/object/list/{BUCKET}", cosa,
            corpo=json.dumps({"prefix": f"{id_}/", "search": "ritaglio_", "limit": 100, "offset": 0,
                              "sortBy": {"column": "name", "order": "asc"}}).encode(),
            intestazioni={"Content-Type": "application/json"})
        voci = self._json(corpo, cosa)
        nomi = [str(v.get("name") or "") for v in voci if isinstance(v, dict) and v.get("id") is not None] \
            if isinstance(voci, list) else []
        return [f"{id_}/{n}" for n in nomi if n.startswith("ritaglio_") and f"{id_}/{n}" != tieni]

    def cancella(self, percorsi: list[str]) -> None:
        if percorsi:
            self._chiama("DELETE", f"/storage/v1/object/{BUCKET}", "cancellazione dei file",
                         corpo=json.dumps({"prefixes": percorsi}).encode(),
                         intestazioni={"Content-Type": "application/json"})


# ----------------------------------------------------------------------------- lavoro

def _una(db: Supabase, ritagliatore: Ritagliatore, id_: str, foto: str, prova: bool) -> str:
    """Lavora una foto. Esito: riuscita, scartata o cambiata (dal membro, nel frattempo).
    Un errore di rete o di Supabase esce come ErroreSupabase: non è uno scarto, la foto si
    riprova alla prossima esecuzione."""
    def scarta(motivo: str) -> str:
        if not prova:
            db.segna_scartata(foto, motivo)
        return "scartata"

    try:
        dati = db.scarica(foto)
    except FotoMancante:
        return scarta("file della foto non trovato")
    try:
        webp = ritagliatore.ritaglia(dati)
    except Scartata as e:
        return scarta(str(e))
    except ModelloGuasto:
        raise
    except Exception as e:  # noqa: BLE001 - una foto strana non deve fermare le altre
        if not ritagliatore.funziona():
            raise ModelloGuasto(type(e).__name__) from None
        return scarta(f"errore durante il ritaglio ({type(e).__name__})")
    if prova:
        return "riuscita"

    ritaglio = f"{id_}/ritaglio_{time.time_ns() // 1_000_000}.webp"
    db.carica(ritaglio, webp)
    try:
        assegnato = db.assegna(id_, foto, ritaglio)
    except ErroreSupabase:
        # Senza risposta il profilo potrebbe essere già aggiornato: il file si cancella solo
        # se di sicuro il profilo non lo usa (meglio un file in più che una carta rotta).
        try:
            if db.ritaglio_di(id_) != ritaglio:
                db.cancella([ritaglio])
        except ErroreSupabase:
            pass
        raise
    try:
        # Riuscito: via i ritagli vecchi del membro. Foto cambiata nel frattempo: via il nuovo.
        db.cancella(db.altri_ritagli(id_, ritaglio) if assegnato else [ritaglio])
    except ErroreSupabase:
        pass  # resta un file in più: lo toglie la pulizia del prossimo ritaglio del membro
    return "riuscita" if assegnato else "cambiata"


def _quante(n: int, una: str, tante: str) -> str:
    return f"{n} {una if n == 1 else tante}"


def _su_stderr(testo: str) -> None:
    print(testo, file=sys.stderr)


def lavora(db: Supabase, ritagliatore: Ritagliatore, *, prova: bool = False, massimo: int = MAX_FOTO,
           stampa: Callable[[str], None] = print, avvisa: Callable[[str], None] = _su_stderr,
           orologio: Callable[[], float] = time.monotonic) -> int:
    attesa = db.in_attesa()
    if not attesa:
        stampa("Nessuna foto da ritagliare.")
        return 0
    stampa(f"{_quante(len(attesa), 'foto', 'foto')} da ritagliare"
           + (f" (al massimo {massimo} per esecuzione)" if len(attesa) > massimo else ""))
    esiti: Counter = Counter()
    problemi: Counter = Counter()
    inizio, di_fila, guasto = orologio(), 0, False
    for id_, foto in attesa[:massimo]:
        if orologio() - inizio > MINUTI_MAX * 60 or di_fila >= ERRORI_DI_FILA:
            break
        try:
            esito = _una(db, ritagliatore, id_, foto, prova)
        except ErroreSupabase as e:
            esito = "errore"
            problemi[str(e)] += 1  # solo operazione, codice e sigla: mai percorsi
        except ModelloGuasto as e:
            avvisa(f"Il modello non funziona ({e}): mi fermo, nessuna foto viene scartata per questo")
            guasto = True
            break
        esiti[esito] += 1
        di_fila = di_fila + 1 if esito == "errore" else 0

    fatte = sum(esiti.values())
    parti = [_quante(esiti["riuscita"], "riuscita", "riuscite"),
             _quante(esiti["scartata"], "scartata", "scartate")]
    if esiti["cambiata"]:
        parti.append(_quante(esiti["cambiata"], "cambiata nel frattempo", "cambiate nel frattempo"))
    if esiti["errore"]:
        parti.append(_quante(esiti["errore"], "rimandata per un errore di rete",
                             "rimandate per errori di rete"))
    if len(attesa) > fatte:
        parti.append(_quante(len(attesa) - fatte, "rimasta per la prossima esecuzione",
                             "rimaste per la prossima esecuzione"))
    stampa(f"{_quante(fatte, 'foto lavorata', 'foto lavorate')} in {orologio() - inizio:.0f} secondi: "
           + ", ".join(parti) + (" (prova: nulla salvato)" if prova else ""))
    for problema, quante in problemi.items():
        avvisa(f"{problema} ({_quante(quante, 'foto', 'foto')})")
    return 1 if guasto or esiti["errore"] else 0


def ritaglia_file(origine: str, destinazione: str, ritagliatore: Ritagliatore,
                  stampa: Callable[[str], None] = print) -> int:
    """Uso locale: ritaglia un file e salva il WebP."""
    try:
        webp = ritagliatore.ritaglia(Path(origine).read_bytes())
    except OSError:
        stampa("Non riesco a leggere il file da ritagliare.")
        return 1
    except Scartata as e:
        stampa(f"Foto scartata: {e}")
        return 1
    except ModelloGuasto as e:
        stampa(f"Il modello non funziona ({e}).")
        return 1
    Path(destinazione).write_bytes(webp)
    stampa(f"Ritaglio salvato: {len(webp) / 1024:.0f} kB")
    return 0


def _annotazione(testo: str, livello: str, env: dict) -> str:
    """Su GitHub Actions diventa un'annotazione del workflow, altrove una riga normale."""
    return f"::{livello}::{testo}" if env.get("GITHUB_ACTIONS") == "true" else testo


def main(argv: list[str] | None = None, env: dict[str, str] | None = None,
         stampa: Callable[[str], None] = print, avvisa: Callable[[str], None] = _su_stderr,
         ritagliatore: Ritagliatore | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    env = dict(os.environ if env is None else env)
    if argv == ["--modello"]:
        stampa(MODELLO)
        return 0
    if len(argv) == 3 and argv[0] == "--file":
        return ritaglia_file(argv[1], argv[2], ritagliatore or Ritagliatore(), stampa)
    if argv not in ([], ["--conta"]):
        avvisa("Uso: ritaglia.py [--conta | --modello | --file foto.jpg ritaglio.webp]")
        return 2

    url = env.get("SUPABASE_URL", "").strip()
    key = env.get("SUPABASE_SECRET_KEY", "").strip()
    if not url.startswith(("https://", "http://")) or not key:
        avvisa(_annotazione("SUPABASE_URL o SUPABASE_SECRET_KEY mancanti", "error", env))
        return 1
    db = Supabase(url, key)
    try:
        if argv == ["--conta"]:
            stampa(str(len(db.in_attesa())))
            return 0
        try:
            massimo = max(1, int(env.get("MAX_FOTO") or MAX_FOTO))
        except ValueError:
            massimo = MAX_FOTO
        return lavora(db, ritagliatore or Ritagliatore(), prova=env.get("DRY_RUN") == "1", massimo=massimo,
                      stampa=stampa, avvisa=lambda testo: avvisa(_annotazione(testo, "error", env)))
    except DatabaseNonAggiornato:
        # Workflow già attivo ma migrazione non ancora applicata: niente da fare, senza errore.
        avvisa(_annotazione("Il database non ha ancora la colonna e la tabella dei ritagli "
                            "(migrazione da applicare): nessuna foto lavorata", "warning", env))
        if argv == ["--conta"]:
            stampa("0")
        return 0
    except ErroreSupabase as e:
        avvisa(_annotazione(str(e), "error", env))
        return 1
    except Exception as e:  # noqa: BLE001 - mai una traccia con dati nei log pubblici
        avvisa(_annotazione(f"Errore imprevisto ({type(e).__name__})", "error", env))
        return 1


if __name__ == "__main__":
    sys.exit(main())
