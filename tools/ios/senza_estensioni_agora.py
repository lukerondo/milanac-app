#!/usr/bin/env python3
"""Toglie dall'app per iPhone le estensioni facoltative di Agora, come per l'APK Android.

La stanza vocale è solo audio e non attiva nessuna estensione (codec video, lip sync, audio
spaziale, volto, riduzione del rumore AI...): sono circa 26 MB dei 58 dell'IPA, e Diawi gratuito
accetta fino a 50 MB. Il pacchetto Swift del plugin agora_rtc_engine le collega però tutte
all'eseguibile Runner, che le caricherebbe all'avvio: cancellate e basta, l'app si chiuderebbe
subito. Per questo, prima di cancellarle:
- controlla che nessun eseguibile usi davvero qualcosa delle estensioni (simboli importati da
  loro): se succede, per esempio con una versione nuova del plugin, le lascia e avvisa;
- rende "deboli" i loro caricamenti (da LC_LOAD_DYLIB a LC_LOAD_WEAK_DYLIB, stessa struttura):
  una libreria debole che manca non ferma l'avvio. AgoraRtcWrapper le carica già così.
Si usa sull'app non firmata (archivio di `flutter build ipa --no-codesign` o `flutter build ios
--no-codesign`): la firma la mette Xcode all'esportazione.

Uso: senza_estensioni_agora.py percorso/Runner.app
"""
from __future__ import annotations

import os
import shutil
import struct
import sys
from pathlib import Path

LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_LAZY_LOAD_DYLIB = 0x20
LC_LOAD_UPWARD_DYLIB = 0x80000023
DYLIB_COMMANDS = {LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB,
                  LC_LOAD_UPWARD_DYLIB}
LC_DYLD_CHAINED_FIXUPS = 0x80000034
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF


class NonVerificabile(Exception):
    """Un eseguibile carica un'estensione in un modo che non si sa rendere innocuo."""


def slices(data: bytes) -> list[int]:
    """Inizio di ogni Mach-O a 64 bit nel file (uno, o più se è "fat"); vuota se non è Mach-O."""
    if len(data) < 32:
        return []
    if struct.unpack_from("<I", data)[0] == MH_MAGIC_64:
        return [0]
    magic, n = struct.unpack_from(">II", data)
    if magic not in (FAT_MAGIC, FAT_MAGIC_64) or not 0 < n < 32:
        return []
    out = []
    for i in range(n):
        if magic == FAT_MAGIC:
            offset = struct.unpack_from(">5I", data, 8 + 20 * i)[2]
        else:
            offset = struct.unpack_from(">IIQQII", data, 8 + 32 * i)[2]
        if struct.unpack_from("<I", data, offset)[0] != MH_MAGIC_64:
            raise NonVerificabile("Mach-O a 32 bit dentro un file fat")
        out.append(offset)
    return out


def dylibs(data: bytes, start: int) -> list[tuple[int, int, str]]:
    """(posizione nel file, comando, nome) di ogni libreria caricata, nell'ordine dei numeri
    (ordinali) con cui gli import la indicano: la prima è la 1."""
    ncmds = struct.unpack_from("<I", data, start + 16)[0]
    pos, out = start + 32, []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, pos)
        if cmd in DYLIB_COMMANDS:
            name_at = struct.unpack_from("<I", data, pos + 8)[0]
            name = data[pos + name_at:pos + size].split(b"\0", 1)[0].decode()
            out.append((pos, cmd, name))
        pos += size
    return out


def strong_imports(data: bytes, start: int) -> set[int]:
    """Ordinali delle librerie da cui l'eseguibile importa almeno un simbolo non debole (letti
    dai chained fixups). Senza chained fixups non si può dire: NonVerificabile."""
    ncmds = struct.unpack_from("<I", data, start + 16)[0]
    pos = start + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, pos)
        if cmd == LC_DYLD_CHAINED_FIXUPS:
            fix = start + struct.unpack_from("<I", data, pos + 8)[0]
            break
        pos += size
    else:
        raise NonVerificabile("senza chained fixups")
    # dyld_chained_fixups_header: version, starts, imports, symbols, imports_count, imports_format
    _, _, imports_at, _, count, fmt = struct.unpack_from("<6I", data, fix)
    imports_at += fix
    used = set()
    for i in range(count):
        if fmt in (1, 2):  # DYLD_CHAINED_IMPORT(_ADDEND): ordinale 8 bit, weak 1 bit
            v = struct.unpack_from("<I", data, imports_at + (4 if fmt == 1 else 8) * i)[0]
            ordinal, weak, special = v & 0xFF, v >> 8 & 1, 0xF0
        elif fmt == 3:  # DYLD_CHAINED_IMPORT_ADDEND64: ordinale 16 bit, weak 1 bit
            v = struct.unpack_from("<Q", data, imports_at + 16 * i)[0]
            ordinal, weak, special = v & 0xFFFF, v >> 16 & 1, 0xFFF0
        else:
            raise NonVerificabile(f"formato degli import {fmt} sconosciuto")
        # 0 = sé stesso; come per dyld, solo i valori sopra 0xF0 (0xFFF0) sono negativi
        # (eseguibile principale, ricerca piatta, ricerca debole).
        if not weak and 0 < ordinal <= special:
            used.add(ordinal)
    return used


def loads_to_weaken(data: bytes, extensions: set[str]) -> list[int]:
    """Posizioni dei caricamenti forti di un'estensione, da rendere deboli. NonVerificabile se
    l'eseguibile usa un simbolo di un'estensione o le carica in un modo che non si sa trattare."""
    out = []
    for start in slices(data):
        loads = dylibs(data, start)
        strong = [(i + 1, pos, cmd) for i, (pos, cmd, name) in enumerate(loads)
                  if is_extension(name, extensions) and cmd != LC_LOAD_WEAK_DYLIB]
        if not strong:
            continue
        if any(cmd != LC_LOAD_DYLIB for _, _, cmd in strong):
            raise NonVerificabile("le carica in un modo particolare")
        used = strong_imports(data, start) & {o for o, _, _ in strong}
        if used:
            raise NonVerificabile("usa " + ", ".join(sorted(loads[o - 1][2].split("/")[-1]
                                                            for o in used)))
        out += [pos for _, pos, _ in strong]
    return out


def is_extension(name: str, extensions: set[str]) -> bool:
    parts = name.split("/")
    return len(parts) >= 2 and parts[-1] in extensions and parts[-2] == f"{parts[-1]}.framework"


def binaries(app: Path, skip: list[Path]) -> list[Path]:
    out = []
    for root, dirs, files in os.walk(app):
        dirs[:] = [d for d in dirs if Path(root, d) not in skip]
        for f in files:
            p = Path(root, f)
            if p.is_symlink():
                continue
            with open(p, "rb") as fh:
                head = fh.read(4)
            if len(head) == 4 and (struct.unpack("<I", head)[0] == MH_MAGIC_64
                                   or struct.unpack(">I", head)[0] in (FAT_MAGIC, FAT_MAGIC_64)):
                out.append(p)
    return out


def size_of(folder: Path) -> int:
    return sum(p.stat().st_size for p in folder.rglob("*") if p.is_file() and not p.is_symlink())


def main(app: Path) -> int:
    if not (app / "Info.plist").is_file():
        raise SystemExit(f"::error::{app} non è un'app (manca Info.plist)")
    found = sorted(p for p in (app / "Frameworks").glob("Agora*Extension.framework") if p.is_dir())
    if not found:
        print("Nessuna estensione di Agora nell'app: niente da togliere.")
        return 0
    names = {p.name.removesuffix(".framework") for p in found}

    # 1. Chi le carica in modo forte non deve usarne nessun simbolo.
    patches: dict[Path, list[int]] = {}
    for path in binaries(app, found):
        try:
            positions = loads_to_weaken(path.read_bytes(), names)
        except NonVerificabile as e:
            print(f"::warning::Estensioni di Agora lasciate nell'app ({path.relative_to(app)}: "
                  f"{e}): l'IPA resta più pesante.")
            return 0
        if positions:
            patches[path] = positions

    # 2. Caricamenti deboli: stessa struttura del comando, cambia solo il suo tipo.
    for path, positions in patches.items():
        data = bytearray(path.read_bytes())
        for pos in positions:
            struct.pack_into("<I", data, pos, LC_LOAD_WEAK_DYLIB)
        path.write_bytes(data)

    # 3. Via le cartelle.
    saved = sum(size_of(p) for p in found)
    for p in found:
        shutil.rmtree(p)

    # 4. Controllo: nessun caricamento forte di una libreria tolta.
    for path in binaries(app, []):
        data = path.read_bytes()
        for start in slices(data):
            for _, cmd, name in dylibs(data, start):
                if is_extension(name, names) and cmd != LC_LOAD_WEAK_DYLIB:
                    raise SystemExit(f"::error::{path.name} carica ancora {name}")

    changed = sum(len(v) for v in patches.values())
    print(f"Tolte {len(found)} estensioni di Agora ({saved / 1e6:.1f} MB non compressi); "
          f"{changed} caricamenti resi deboli in {', '.join(sorted(p.name for p in patches)) or '-'}.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Uso: senza_estensioni_agora.py percorso/Runner.app")
    sys.exit(main(Path(sys.argv[1])))
