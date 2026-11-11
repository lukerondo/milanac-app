"""Prove di testflight.py con un App Store Connect finto (nessuna chiamata vera)."""
from __future__ import annotations

import contextlib
import io
import sys
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import testflight as tf  # noqa: E402


class FakeAsc:
    def __init__(self):
        self.apps = [{"id": "A1", "attributes": {"bundleId": tf.BUNDLE_ID, "name": "MILANAC"}}]
        self.builds = []
        self.groups = []
        self.calls = []
        self.review_error = None
        # Stati che la build attraversa, uno per ogni lettura.
        self.states = ["PROCESSING", "VALID"]
        # Informazioni sul test compilate su App Store Connect.
        self.app_localizations = [{"id": "L1", "attributes": {
            "locale": "it", "description": "App del club", "feedbackEmail": "club@example.org",
            "privacyPolicyUrl": "https://example.org/privacy"}}]
        self.review_detail = {"contactFirstName": "Mario", "contactLastName": "Rossi",
                              "contactPhone": "+39 333 0000000", "contactEmail": "m@example.org",
                              "demoAccountRequired": True, "demoAccountName": "prova@example.org",
                              "demoAccountPassword": "segreta"}
        self.build_localizations = []
        self.bodies = []

    def pages(self, path):
        url = urlparse(path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        if url.path == "/apps":
            return [a for a in self.apps if a["attributes"]["bundleId"] == q["filter[bundleId]"]]
        if url.path == "/builds":
            if "filter[version]" in q:
                found = [b for b in self.builds if b["attributes"]["version"] == q["filter[version]"]]
                if found and self.states:
                    found[0]["attributes"]["processingState"] = self.states.pop(0)
                return found
            return self.builds
        if url.path == "/betaGroups":
            return self.groups
        if url.path == "/apps/A1/betaAppLocalizations":
            return self.app_localizations
        if url.path.startswith("/builds/") and url.path.endswith("/betaBuildLocalizations"):
            return self.build_localizations
        raise AssertionError(path)

    def call(self, method, path, body=None, quiet=False):
        if method == "GET":
            if path == "/apps/A1":
                return {"data": {"id": "A1", "attributes": {"primaryLocale": "it"}}}
            if path == "/apps/A1/betaAppReviewDetail":
                return {"data": {"id": "D1", "attributes": self.review_detail}}
            raise AssertionError(path)
        self.calls.append((method, path))
        self.bodies.append(body)
        if path == "/betaGroups":
            g = {"id": "G9", "attributes": body["data"]["attributes"]}
            self.groups.append(g)
            return {"data": g}
        if path == "/betaAppReviewSubmissions" and self.review_error:
            raise tf.ApiError(*self.review_error)
        return {}


def quiet(fn, *a, **k):
    with contextlib.redirect_stdout(io.StringIO()) as out:
        return fn(*a, **k), out.getvalue()


class TestFlight(unittest.TestCase):
    def test_app_e_numero_della_build(self):
        asc = FakeAsc()
        self.assertEqual(tf.find_app(asc.pages)["id"], "A1")
        self.assertEqual(tf.next_build_number(asc.pages, "A1"), 1)
        asc.builds = [{"id": "b", "attributes": {"version": v}} for v in ("3", "12", "7", "x")]
        self.assertEqual(tf.next_build_number(asc.pages, "A1"), 13)

    def test_app_mancante_spiega_cosa_fare(self):
        asc = FakeAsc()
        asc.apps = []
        with self.assertRaises(SystemExit) as e:
            tf.find_app(asc.pages)
        self.assertIn("Nuova app", str(e.exception))

    def test_distribuzione_crea_il_gruppo_e_chiede_la_revisione(self):
        asc = FakeAsc()
        asc.builds = [{"id": "B5", "attributes": {"version": "5",
                                                  "usesNonExemptEncryption": False}}]
        esito, out = quiet(tf.distribute, asc.call, asc.pages, "A1", "5", pause=0,
                           sleep=lambda _: None)
        self.assertEqual(esito, "in revisione")
        self.assertEqual(asc.calls, [
            ("POST", "/betaGroups"),
            ("POST", "/betaGroups/G9/relationships/builds"),
            ("POST", "/betaBuildLocalizations"),
            ("POST", "/betaAppReviewSubmissions"),
        ])
        self.assertTrue(asc.groups[0]["attributes"]["publicLinkEnabled"])
        # Il "Cosa testare" che Apple chiede per i tester esterni, nella lingua dell'app.
        whats_new = asc.bodies[2]["data"]
        self.assertEqual(whats_new["attributes"]["locale"], "it")
        self.assertEqual(whats_new["attributes"]["whatsNew"], tf.WHATS_NEW)
        self.assertEqual(whats_new["relationships"]["build"]["data"]["id"], "B5")
        self.assertIn("PROCESSING", out)
        self.assertNotIn("http", out)
        self.assertNotIn("Da controllare", out)

    def test_gruppo_esistente_e_informazioni_sul_test_mancanti(self):
        asc = FakeAsc()
        asc.builds = [{"id": "B5", "attributes": {"version": "5"}}]
        asc.groups = [{"id": "G1", "attributes": {"name": "Club", "isInternalGroup": False}}]
        asc.app_localizations = []
        asc.review_detail = {}
        asc.review_error = (409, '{"errors":[{"detail":"Missing beta app review detail"}]}')
        esito, out = quiet(tf.distribute, asc.call, asc.pages, "A1", "5", pause=0,
                           sleep=lambda _: None)
        self.assertEqual(esito, "nel gruppo, revisione non richiesta")
        self.assertEqual(asc.calls[0], ("POST", "/betaGroups/G1/relationships/builds"))
        self.assertIn("Informazioni sul test: descrizione dell'app beta ed email", out)
        self.assertIn("nome del contatto", out)

    def test_tutto_compilato_ma_apple_rifiuta_lo_stesso(self):
        asc = FakeAsc()
        asc.builds = [{"id": "B5", "attributes": {"version": "5",
                                                  "usesNonExemptEncryption": False}}]
        asc.groups = [{"id": "G1", "attributes": {"name": "Club", "isInternalGroup": False}}]
        asc.review_error = (422, '{"errors":[{"title":"Missing required information"}]}')
        esito, out = quiet(tf.distribute, asc.call, asc.pages, "A1", "5", pause=0,
                           sleep=lambda _: None)
        self.assertEqual(esito, "nel gruppo, revisione non richiesta")
        self.assertIn("risultano compilate", out)
        self.assertIn("Missing required information", out)

    def test_dice_quali_campi_mancano_senza_mostrarne_i_valori(self):
        asc = FakeAsc()
        asc.builds = [{"id": "B5", "attributes": {"version": "5"}}]
        asc.groups = [{"id": "G1", "attributes": {"name": "Club", "isInternalGroup": False}}]
        asc.app_localizations[0]["attributes"]["privacyPolicyUrl"] = ""
        asc.review_detail.update(contactPhone="", demoAccountPassword=None)
        asc.review_error = (422, '{"errors":[{"code":"ENTITY_UNPROCESSABLE.MISSING_REQUIRED_DATA"}]}')
        esito, out = quiet(tf.distribute, asc.call, asc.pages, "A1", "5", pause=0,
                           sleep=lambda _: None)
        self.assertEqual(esito, "nel gruppo, revisione non richiesta")
        for campo in ("informativa sulla privacy", "telefono del contatto",
                      "password dell'account di prova", "conformità all'esportazione"):
            self.assertIn(campo, out)
        self.assertNotIn("email per i commenti", out)
        self.assertIn('"build" = 5', out)
        for valore in ("club@example.org", "Mario", "prova@example.org", "m@example.org"):
            self.assertNotIn(valore, out)

    def test_cosa_testare_esistente_resta_o_si_sostituisce_con_le_novita(self):
        asc = FakeAsc()
        asc.builds = [{"id": "B5", "attributes": {"version": "5",
                                                  "usesNonExemptEncryption": False}}]
        asc.groups = [{"id": "G1", "attributes": {"name": "Club", "isInternalGroup": False}}]
        asc.build_localizations = [{"id": "W1", "attributes": {"locale": "it",
                                                               "whatsNew": "Già scritto"}}]
        quiet(tf.distribute, asc.call, asc.pages, "A1", "5", pause=0, sleep=lambda _: None)
        self.assertNotIn(("PATCH", "/betaBuildLocalizations/W1"), asc.calls)

        asc.states = ["VALID"]
        quiet(tf.distribute, asc.call, asc.pages, "A1", "5", whats_new="Colonna sonora",
              pause=0, sleep=lambda _: None)
        self.assertIn(("PATCH", "/betaBuildLocalizations/W1"), asc.calls)
        patch = asc.bodies[asc.calls.index(("PATCH", "/betaBuildLocalizations/W1"))]
        self.assertEqual(patch["data"]["attributes"]["whatsNew"], "Colonna sonora")

    def test_build_scartata_o_mai_pronta(self):
        asc = FakeAsc()
        asc.builds = [{"id": "B5", "attributes": {"version": "5"}}]
        asc.states = ["INVALID"]
        with self.assertRaises(SystemExit) as e:
            quiet(tf.wait_for_build, asc.pages, "A1", "5", pause=0, sleep=lambda _: None)
        self.assertIn("scartato", str(e.exception))
        asc.builds = []
        with self.assertRaises(SystemExit) as e:
            quiet(tf.wait_for_build, asc.pages, "A1", "5", timeout=60, pause=30,
                  sleep=lambda _: None)
        self.assertIn("non è pronta", str(e.exception))


if __name__ == "__main__":
    unittest.main()
