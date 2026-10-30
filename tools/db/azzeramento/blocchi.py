"""Blocchi di azzera.sql: elenco, bucket da svuotare, file senza alcuni blocchi.

Un blocco va dalla riga "-- ==== BLOCCO <nome> ..." alla riga "-- ==== FINE <nome>".
Nella riga d'inizio: "obbligatorio" (non si toglie) e "file: a, b" (bucket dello Storage
che svuota_storage.py svuota per quel blocco).
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

FILE_SQL = Path(__file__).with_name("azzera.sql")

_INIZIO = re.compile(r"^-- ==== BLOCCO (\w+)(.*)$")
_FINE = re.compile(r"^-- ==== FINE (\w+)\s*$")
_FILE = re.compile(r"file:\s*([a-z0-9_, -]+)")


@dataclass
class Blocco:
    nome: str
    obbligatorio: bool
    bucket: list[str]
    inizio: int  # righe del file (da 0), comprese
    fine: int


def leggi(testo: str) -> list[Blocco]:
    blocchi: list[Blocco] = []
    aperto: tuple[str, str, int] | None = None
    for i, riga in enumerate(testo.splitlines()):
        m = _INIZIO.match(riga)
        if m:
            if aperto:
                raise ValueError(f"Il blocco {aperto[0]} non è chiuso prima di {m.group(1)}")
            aperto = (m.group(1), m.group(2), i)
            continue
        m = _FINE.match(riga)
        if m:
            if not aperto or aperto[0] != m.group(1):
                raise ValueError(f"FINE {m.group(1)} senza il suo BLOCCO")
            nome, attributi, inizio = aperto
            file = _FILE.search(attributi)
            bucket = [b.strip() for b in file.group(1).split(",") if b.strip()] if file else []
            blocchi.append(Blocco(nome, "obbligatorio" in attributi, bucket, inizio, i))
            aperto = None
    if aperto:
        raise ValueError(f"Il blocco {aperto[0]} non è chiuso")
    nomi = [b.nome for b in blocchi]
    if len(set(nomi)) != len(nomi):
        raise ValueError("Due blocchi con lo stesso nome")
    if not any(b.obbligatorio for b in blocchi):
        raise ValueError("Manca il blocco obbligatorio (account)")
    return blocchi


def senza(testo: str, nomi: set[str]) -> str:
    """Il testo senza i blocchi indicati (solo blocchi da decidere)."""
    blocchi = leggi(testo)
    sconosciuti = nomi - {b.nome for b in blocchi}
    if sconosciuti:
        raise ValueError(f"Blocchi inesistenti: {', '.join(sorted(sconosciuti))}")
    obbligatori = sorted(b.nome for b in blocchi if b.obbligatorio and b.nome in nomi)
    if obbligatori:
        raise ValueError(f"Blocchi obbligatori, non si tolgono: {', '.join(obbligatori)}")
    via = {i for b in blocchi if b.nome in nomi for i in range(b.inizio, b.fine + 1)}
    return "".join(r for i, r in enumerate(testo.splitlines(keepends=True)) if i not in via)


def bucket_da_svuotare(testo: str) -> list[str]:
    visti: list[str] = []
    for b in leggi(testo):
        for nome in b.bucket:
            if nome not in visti:
                visti.append(nome)
    return visti
