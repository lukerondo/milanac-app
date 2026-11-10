#!/usr/bin/env python3
"""Su Supabase le chiamate dall'app passano dall'estensione safeupdate, che rifiuta DELETE e
UPDATE senza WHERE ("DELETE requires a WHERE clause"). Sul PostgreSQL dei test l'estensione non
c'è, quindi lo si controlla qui: nelle funzioni definite dalle migrazioni (l'ultima versione di
ognuna) ogni DELETE e UPDATE deve avere una WHERE. Per svuotare una tabella: "where true".

Uso: safeupdate_check.py supabase/migrations/*.sql
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

FUNCTION = re.compile(
    r"create\s+(?:or\s+replace\s+)?function\s+([a-z0-9_.\"]+)\s*\((.*?)\)\s*returns.*?\$(\w*)\$(.*?)\$\3\$",
    re.I | re.S)
COMMENT = re.compile(r"--[^\n]*")
STATEMENT = re.compile(r"\b(delete\s+from|update)\s+([a-z0-9_.\"]+)", re.I)


def statements(body: str):
    """Le istruzioni del corpo, divise sui punto e virgola (senza commenti né stringhe)."""
    body = COMMENT.sub("", body)
    body = re.sub(r"'(?:[^']|'')*'", "''", body)
    for part in body.split(";"):
        yield " ".join(part.split())


def problems(files: list[Path]) -> list[str]:
    latest: dict[str, tuple[str, str]] = {}
    for path in files:
        for m in FUNCTION.finditer(path.read_text()):
            name = m.group(1).lower().replace("public.", "").strip('"')
            args = re.sub(r"\s+", " ", m.group(2).lower())
            latest[f"{name}({args})"] = (path.name, m.group(4))
    found = []
    for name, (file, body) in sorted(latest.items()):
        for st in statements(body):
            for m in STATEMENT.finditer(st):
                before = st[:m.start()].lower().split()[-1:] or [""]
                # "on conflict ... do update set" e "select ... for update" non sono istruzioni a sé.
                if before[0] in ("do", "for"):
                    continue
                if not re.search(r"\bwhere\b", st[m.start():], re.I):
                    found.append(f"{file}: {name.split('(')[0]}: {st[m.start():][:80]}")
    return found


def main(argv: list[str]) -> int:
    found = problems([Path(a) for a in argv[1:]])
    for f in found:
        print(f"Senza WHERE (Supabase lo rifiuta): {f}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
