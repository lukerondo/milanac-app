#!/usr/bin/env python3
"""Lancia azzera.sql sul database tramite la Management API di Supabase (come migrate_api.py).

Conta le righe di ogni tabella, poi:
  DRY_RUN=1 (predefinito)  prova: tutto in una transazione che non arriva mai al commit.
                           Alla fine un errore voluto (AZZERAMENTO_PROVA) la annulla e porta
                           fuori i conteggi "dopo"; poi si ricontrolla che non sia cambiato niente.
  DRY_RUN=0                azzeramento vero (serve anche CONFERMA=AZZERA), poi riconta.
Stampa solo nomi di tabelle e numeri di righe: i log di GitHub Actions sono pubblici.

Variabili d'ambiente:
  SUPABASE_ACCESS_TOKEN     token personale (sbp_...)
  SUPABASE_PROJECT_REF      riferimento del progetto (es. bxtnvgnxfyzwamfdnmkx)
  DRY_RUN                   1 = prova (predefinito), 0 = azzeramento vero
  CONFERMA                  deve valere AZZERA per l'azzeramento vero
  NUOVA_PASSWORD_DIRETTIVO  facoltativa: nuova password del Direttivo (blocco password_direttivo)

Senza rete, per le prove in locale:
  esegui.py --stampa prova|vero [--senza blocco,...]  stampa l'SQL che verrebbe inviato
                                                      (con l'eventuale password: solo in locale)
  esegui.py --rapporto FILE                           legge il rapporto della prova da un errore
"""
from __future__ import annotations

import argparse
import os
import re
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import blocchi  # noqa: E402
from migrate_api import query  # noqa: E402

# Righe di ogni tabella di public e auth e file di ogni bucket (un'unica istruzione SQL).
CONTEGGI = r"""
select nome, righe from (
  select format('%s.%s', n.nspname, c.relname) as nome,
         (xpath('/row/n/text()', query_to_xml(
            format('select count(*) as n from %I.%I', n.nspname, c.relname),
            false, true, '')))[1]::text::bigint as righe
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'auth') and c.relkind in ('r', 'p') and not c.relispartition
    and has_table_privilege(c.oid, 'select')
  union all
  select format('storage.objects:%s', b.id),
         (select count(*) from storage.objects o where o.bucket_id = b.id)
  from storage.buckets b
) t
where nome ~ '^[a-z0-9_.:-]+$'
""".strip()

# Fine della prova: le tabelle cambiate, dentro il messaggio dell'errore che annulla tutto.
RAPPORTO = f"""
do $$
declare testo text;
begin
  select string_agg(format('%s=%s,%s', p.nome, p.righe, coalesce(d.righe, 0)), ';' order by p.nome)
    into testo
  from _azz_rapporto p left join ({CONTEGGI}) d using (nome)
  where d.righe is distinct from p.righe;
  raise exception 'AZZERAMENTO_PROVA[%]FINE', coalesce(testo, '');
end $$;
rollback;
""".strip()

MARCA = re.compile(r"AZZERAMENTO_PROVA\[([a-z0-9_.:=,;-]*)\]FINE")


def corpo(testo: str) -> str:
    """Quello che sta tra "begin;" e "commit;" (una volta sola ciascuno, a inizio riga)."""
    righe = testo.splitlines()
    inizi = [i for i, r in enumerate(righe) if r.strip().lower() == "begin;"]
    fini = [i for i, r in enumerate(righe) if r.strip().lower() == "commit;"]
    if len(inizi) != 1 or len(fini) != 1 or inizi[0] > fini[0]:
        raise SystemExit("azzera.sql deve avere un solo 'begin;' e un solo 'commit;', in quest'ordine")
    dopo = [r for r in righe[fini[0] + 1:] if r.strip() and not r.strip().startswith("--")]
    if dopo:
        raise SystemExit("azzera.sql: dopo 'commit;' non deve esserci altro")
    return "\n".join(righe[inizi[0] + 1:fini[0]])


def letterale(valore: str) -> str:
    """Stringa SQL tra dollari con un'etichetta casuale (nessun carattere da proteggere)."""
    if "\x00" in valore:
        raise SystemExit("Valore non valido")
    while True:
        tag = f"$v{secrets.token_hex(6)}$"
        if tag not in valore:
            return f"{tag}{valore}{tag}"


def componi(modo: str, togli: set[str], password: str | None) -> str:
    testo = blocchi.FILE_SQL.read_text(encoding="utf-8")
    nomi = {b.nome for b in blocchi.leggi(testo)}
    if togli:
        testo = blocchi.senza(testo, togli)
    if password is not None and "password_direttivo" not in nomi - togli:
        raise SystemExit("C'è una nuova password del Direttivo ma il blocco password_direttivo è stato tolto")
    parti = ["begin;"]
    if password is not None:
        # Dentro un blocco DO: nessuna istruzione restituisce la password come risultato.
        parti.append("do $$ begin perform set_config('azzeramento.nuova_password_direttivo', "
                     f"{letterale(password)}, true); end $$;")
    if modo == "prova":
        parti.append(f"create temp table _azz_rapporto on commit drop as\n{CONTEGGI};")
    parti.append(corpo(testo))
    parti.append(RAPPORTO if modo == "prova" else "commit;")
    return "\n".join(parti) + "\n"


def leggi_rapporto(testo: str) -> dict[str, tuple[int, int]] | None:
    m = MARCA.search(testo)
    if not m:
        return None
    cambiate = {}
    for voce in filter(None, m.group(1).split(";")):
        nome, numeri = voce.split("=")
        prima, dopo = numeri.split(",")
        cambiate[nome] = (int(prima), int(dopo))
    return cambiate


def conteggi(ref: str, token: str) -> dict[str, int]:
    return {r["nome"]: int(r["righe"]) for r in query(ref, token, CONTEGGI)}


def tabella(prima: dict[str, int], dopo: dict[str, int], titolo_dopo: str) -> None:
    nomi = sorted(set(prima) | set(dopo))
    largo = max(len(n) for n in nomi)
    print(f"{'tabella'.ljust(largo)}  {'prima':>7}  {titolo_dopo:>7}")
    for n in nomi:
        a, b = prima.get(n, 0), dopo.get(n, 0)
        segno = "  ←" if a != b else ""
        print(f"{n.ljust(largo)}  {a:>7}  {b:>7}{segno}")


def stampa_rapporto(percorso: str) -> int:
    cambiate = leggi_rapporto(Path(percorso).read_text(encoding="utf-8", errors="replace"))
    if cambiate is None:
        print("Nessun rapporto AZZERAMENTO_PROVA: la prova si è fermata per un altro errore.")
        return 1
    for nome, (a, b) in sorted(cambiate.items()):
        print(f"{nome} {a} -> {b}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stampa", choices=["prova", "vero"])
    ap.add_argument("--senza", default="", help="blocchi da decidere da togliere, separati da virgole")
    ap.add_argument("--rapporto", metavar="FILE")
    args = ap.parse_args()
    togli = {s.strip() for s in args.senza.split(",") if s.strip()}
    password = os.environ.get("NUOVA_PASSWORD_DIRETTIVO") or None
    if password is not None and len(password) < 8:
        print("::error::NUOVA_PASSWORD_DIRETTIVO deve avere almeno 8 caratteri")
        return 1

    if args.rapporto:
        return stampa_rapporto(args.rapporto)
    if args.stampa:
        sys.stdout.write(componi(args.stampa, togli, password))
        return 0

    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    prova = os.environ.get("DRY_RUN", "1") != "0"
    if not token.startswith("sbp_"):
        print("::error::SUPABASE_ACCESS_TOKEN deve iniziare con sbp_ (token personale)")
        return 1
    if not re.fullmatch(r"[a-z0-9]{10,40}", ref):
        print("::error::SUPABASE_PROJECT_REF mancante o non valido")
        return 1
    if not prova and os.environ.get("CONFERMA") != "AZZERA":
        print("::error::Per l'azzeramento vero serve CONFERMA=AZZERA")
        return 1

    testo = blocchi.FILE_SQL.read_text(encoding="utf-8")
    elenco = [b for b in blocchi.leggi(testo) if b.nome not in togli]
    print("Modalità:", "PROVA (nessuna modifica)" if prova else "AZZERAMENTO VERO")
    print("Blocchi:", ", ".join(b.nome + (" (obbligatorio)" if b.obbligatorio else "") for b in elenco))
    print("Nuova password del Direttivo:", "sì" if password else "no (resta quella di prima)")
    sql = componi("prova" if prova else "vero", togli, password)

    prima = conteggi(ref, token)
    if prova:
        try:
            risposta = query(ref, token, sql)
            cambiate = leggi_rapporto(str(risposta))
        except SystemExit as e:  # migrate_api.query trasforma gli errori HTTP in SystemExit
            cambiate = leggi_rapporto(str(e))
            if cambiate is None:
                print(f"::error::La prova si è fermata prima della fine: {e}")
                return 1
        if cambiate is None:
            print("::error::La prova non ha restituito il rapporto atteso")
            return 1
        dopo = dict(prima)
        dopo.update({nome: b for nome, (_, b) in cambiate.items()})
        print()
        tabella(prima, dopo, "dopo*")
        print("* dopo = come sarebbe, simulato dentro la transazione annullata.")
        ancora = conteggi(ref, token)
        diverse = sorted(n for n in prima if ancora.get(n) != prima[n])
        if diverse:
            print(f"Nota: nel frattempo sono cambiate altre righe (attività dell'app): {', '.join(diverse)}")
        else:
            print("Database invariato: la prova è stata annullata.")
        return 0

    query(ref, token, sql)
    dopo = conteggi(ref, token)
    print()
    tabella(prima, dopo, "dopo")
    # Gli account di prima non ci sono più (lo controlla azzera.sql prima del commit):
    # se qui ne compare uno, qualcuno si è registrato subito dopo.
    if dopo.get("auth.users", 0):
        print(f"::warning::Account nuovi dopo l'azzeramento: {dopo['auth.users']}")
    print("Azzeramento fatto.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
