"""Prove di senza_estensioni_agora.py su app finte, con eseguibili Mach-O minimi costruiti qui."""
from __future__ import annotations

import contextlib
import io
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import senza_estensioni_agora as sea  # noqa: E402

LIP = "AgoraLipSyncExtension"
SPATIAL = "AgoraSpatialAudioExtension"


def rpath(name: str) -> str:
    return f"@rpath/{name}.framework/{name}"


def macho(loads: list[tuple[int, str]], imports: list[tuple[int, bool]] | None = None,
          fmt: int = 1) -> bytes:
    """Mach-O arm64 con i caricamenti dati e, se imports non è None, i chained fixups con quegli
    import: (ordinale della libreria, debole)."""
    cmds = b""
    for cmd, name in loads:
        raw = name.encode() + b"\0"
        size = (24 + len(raw) + 7) // 8 * 8
        cmds += struct.pack("<6I", cmd, size, 24, 2, 0x10000, 0x10000) + raw.ljust(size - 24, b"\0")
    ncmds, blob = len(loads), b""
    if imports is not None:
        table = b""
        for ordinal, weak in imports:
            if fmt == 3:
                table += struct.pack("<QQ", ordinal | int(weak) << 16, 0)
            else:
                table += struct.pack("<I", ordinal | int(weak) << 8) + b"\0" * (4 if fmt == 2 else 0)
        # Come nei file veri, prima degli import c'è altro (qui 8 byte che, letti per errore come
        # import, sarebbero un uso forte della libreria 2).
        starts = struct.pack("<II", 2, 2)
        blob = struct.pack("<7I", 0, 28, 28 + len(starts), 28 + len(starts) + len(table),
                           len(imports), fmt, 0) + starts + table
        cmds += struct.pack("<4I", sea.LC_DYLD_CHAINED_FIXUPS, 16, 32 + len(cmds) + 16, len(blob))
        ncmds += 1
    header = struct.pack("<IiiIIIII", sea.MH_MAGIC_64, 0x0100000C, 0, 2, ncmds, len(cmds), 0, 0)
    return header + cmds + blob


def fat(*slices: bytes) -> bytes:
    pos = 8 + 20 * len(slices)
    entries, body = b"", b""
    for s in slices:
        start = (pos + 15) // 16 * 16
        body += b"\0" * (start - pos) + s
        entries += struct.pack(">5I", 0x0100000C, 0, start, len(s), 4)
        pos = start + len(s)
    return struct.pack(">II", sea.FAT_MAGIC, len(slices)) + entries + body


def kinds(data: bytes) -> list[dict[str, int]]:
    return [{name.split("/")[-1]: cmd for _, cmd, name in sea.dylibs(data, s)}
            for s in sea.slices(data)]


class SenzaEstensioni(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.app = Path(self.tmp.name, "Runner.app")
        (self.app / "Frameworks").mkdir(parents=True)
        (self.app / "Info.plist").write_text("<plist/>")
        (self.app / "flutter_assets").mkdir()
        (self.app / "flutter_assets" / "intro.txt").write_text("non è un eseguibile")
        self.framework("Flutter", macho([]))
        self.framework("AgoraRtcKit", macho([]))
        # Come quello vero: le estensioni le carica già in modo debole e non ha chained fixups.
        self.framework("AgoraRtcWrapper", macho([(sea.LC_LOAD_DYLIB, rpath("AgoraRtcKit")),
                                                 (sea.LC_LOAD_WEAK_DYLIB, rpath(LIP)),
                                                 (sea.LC_LOAD_WEAK_DYLIB, rpath(SPATIAL))]))
        # Le estensioni non si controllano: anche se una carica l'altra in modo forte (e senza
        # chained fixups) vanno via tutte e due insieme.
        self.framework(LIP, macho([(sea.LC_LOAD_DYLIB, rpath("AgoraRtcKit"))]))
        self.framework(SPATIAL, macho([(sea.LC_LOAD_DYLIB, rpath("AgoraRtcKit")),
                                       (sea.LC_LOAD_DYLIB, rpath(LIP))]))
        for ext in (LIP, SPATIAL):
            (self.app / "Frameworks" / f"{ext}.framework" / "Info.plist").write_text("<plist/>")

    def tearDown(self):
        self.tmp.cleanup()

    def framework(self, name: str, binary: bytes) -> None:
        folder = self.app / "Frameworks" / f"{name}.framework"
        folder.mkdir(exist_ok=True)
        (folder / name).write_bytes(binary)

    def runner(self, binary: bytes) -> Path:
        path = self.app / "Runner"
        path.write_bytes(binary)
        return path

    def run_main(self) -> str:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(sea.main(self.app), 0)
        return out.getvalue()

    def extensions_left(self) -> list[str]:
        return sorted(p.name for p in (self.app / "Frameworks").glob("Agora*Extension.framework"))

    def test_toglie_le_estensioni_e_rende_deboli_i_caricamenti(self):
        runner = self.runner(macho(
            [(sea.LC_LOAD_DYLIB, rpath("Flutter")), (sea.LC_LOAD_DYLIB, rpath("AgoraRtcKit")),
             (sea.LC_LOAD_DYLIB, rpath(LIP)), (sea.LC_LOAD_DYLIB, rpath(SPATIAL))],
            # Usa Flutter e Agora; da LipSync solo un import debole; 0xFF = eseguibile principale.
            imports=[(1, False), (2, False), (3, True), (0xFF, False)]))
        wrapper = (self.app / "Frameworks/AgoraRtcWrapper.framework/AgoraRtcWrapper").read_bytes()

        out = self.run_main()

        self.assertEqual(self.extensions_left(), [])
        self.assertEqual(kinds(runner.read_bytes()), [{
            "Flutter": sea.LC_LOAD_DYLIB, "AgoraRtcKit": sea.LC_LOAD_DYLIB,
            LIP: sea.LC_LOAD_WEAK_DYLIB, SPATIAL: sea.LC_LOAD_WEAK_DYLIB}])
        self.assertEqual(
            (self.app / "Frameworks/AgoraRtcWrapper.framework/AgoraRtcWrapper").read_bytes(), wrapper)
        self.assertTrue((self.app / "Frameworks/AgoraRtcKit.framework/AgoraRtcKit").exists())
        self.assertTrue((self.app / "flutter_assets/intro.txt").exists())
        self.assertIn("Tolte 2 estensioni di Agora", out)
        self.assertIn("2 caricamenti resi deboli in Runner", out)
        # Una seconda volta non c'è più niente da fare.
        self.assertIn("niente da togliere", self.run_main())

    def test_le_lascia_se_runner_ne_usa_un_simbolo(self):
        original = macho([(sea.LC_LOAD_DYLIB, rpath("Flutter")), (sea.LC_LOAD_DYLIB, rpath(LIP))],
                         imports=[(1, False), (2, False)])
        runner = self.runner(original)

        out = self.run_main()

        self.assertIn("::warning::", out)
        self.assertIn(LIP, out)
        self.assertEqual(runner.read_bytes(), original)
        self.assertEqual(self.extensions_left(), [f"{LIP}.framework", f"{SPATIAL}.framework"])

    def test_le_lascia_senza_chained_fixups(self):
        original = macho([(sea.LC_LOAD_DYLIB, rpath(LIP))])
        runner = self.runner(original)

        self.assertIn("(Runner: senza chained fixups)", self.run_main())
        self.assertEqual(runner.read_bytes(), original)
        self.assertEqual(len(self.extensions_left()), 2)

    def test_le_lascia_con_un_eseguibile_a_32_bit(self):
        thin32 = struct.pack("<7I", 0xFEEDFACE, 12, 0, 2, 0, 0, 0)
        original = fat(macho([(sea.LC_LOAD_DYLIB, rpath(LIP))], imports=[]), thin32)
        runner = self.runner(original)

        self.assertIn("Runner: Mach-O a 32 bit", self.run_main())
        self.assertEqual(runner.read_bytes(), original)
        self.assertEqual(len(self.extensions_left()), 2)

    def test_ordinale_240_e_una_libreria(self):
        # dyld considera negativi (speciali) solo i valori sopra 0xF0: la libreria 240 è vera.
        loads = [(sea.LC_LOAD_DYLIB, f"/usr/lib/lib{i}.dylib") for i in range(239)]
        original = macho(loads + [(sea.LC_LOAD_DYLIB, rpath(LIP))], imports=[(240, False)])
        runner = self.runner(original)

        self.assertIn(f"usa {LIP}", self.run_main())
        self.assertEqual(runner.read_bytes(), original)

    def test_le_lascia_se_caricate_in_modo_particolare(self):
        original = macho([(sea.LC_REEXPORT_DYLIB, rpath(SPATIAL))], imports=[])
        runner = self.runner(original)

        self.assertIn("modo particolare", self.run_main())
        self.assertEqual(runner.read_bytes(), original)
        self.assertEqual(len(self.extensions_left()), 2)

    def test_eseguibile_fat_con_import_a_64_bit(self):
        thin = macho([(sea.LC_LOAD_DYLIB, rpath("Flutter")), (sea.LC_LOAD_DYLIB, rpath(SPATIAL))],
                     imports=[(1, False), (0xFFFF, False)], fmt=3)
        runner = self.runner(fat(thin, thin))

        self.run_main()

        self.assertEqual(kinds(runner.read_bytes()),
                         [{"Flutter": sea.LC_LOAD_DYLIB, SPATIAL: sea.LC_LOAD_WEAK_DYLIB}] * 2)
        self.assertEqual(self.extensions_left(), [])

    def test_import_con_addendo(self):
        # Formato 2: 8 byte per import; il secondo usa LipSync.
        original = macho([(sea.LC_LOAD_DYLIB, rpath("Flutter")), (sea.LC_LOAD_DYLIB, rpath(LIP))],
                         imports=[(1, False), (2, False)], fmt=2)
        runner = self.runner(original)

        self.assertIn(f"usa {LIP}", self.run_main())
        self.assertEqual(runner.read_bytes(), original)

    def test_senza_estensioni_non_fa_niente(self):
        for ext in (LIP, SPATIAL):
            for f in (self.app / "Frameworks" / f"{ext}.framework").iterdir():
                f.unlink()
            (self.app / "Frameworks" / f"{ext}.framework").rmdir()
        self.runner(macho([(sea.LC_LOAD_DYLIB, rpath("Flutter"))], imports=[(1, False)]))

        self.assertIn("niente da togliere", self.run_main())

    def test_cartella_che_non_e_un_app(self):
        (self.app / "Info.plist").unlink()
        with self.assertRaises(SystemExit):
            sea.main(self.app)


if __name__ == "__main__":
    unittest.main()
