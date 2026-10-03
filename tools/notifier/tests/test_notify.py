import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import notify  # noqa: E402


class FakeDb:
    def __init__(self, tables):
        self.tables = tables
        self.queries = []
        self.marked = {}

    def select(self, table, query):
        self.queries.append((table, query))
        return self.tables.get(table, [])

    def mark_notified(self, table, ids):
        self.marked[table] = ids


class MessagesTest(unittest.TestCase):
    def test_aggiornamento_usa_la_notizia_piu_recente(self):
        msg = notify.update_message([
            {"title": "Title Update 1.0.3", "published_at": "2026-10-01T10:00:00+00:00"},
            {"title": "Title Update 1.0.4", "published_at": "2026-10-02T10:00:00+00:00"},
        ])
        self.assertIn("1.0.4", msg["body"])
        self.assertEqual(msg["route"], "/")
        self.assertIsNone(notify.update_message([]))

    def test_evento_con_ora_italiana(self):
        msg = notify.event_message({
            "type": "torneo", "title": "FVPA vs Dinamo",
            "starts_at": "2026-10-05T19:30:00+00:00",  # 21:30 a Roma (ora legale)
        })
        self.assertEqual(msg["body"], "FVPA vs Dinamo · lun 5/10 alle 21:30")
        self.assertIn("Partita di torneo", msg["title"])

    def test_promemoria(self):
        msg = notify.reminder_message([
            {"title": "Allenamento", "starts_at": "2026-10-05T19:00:00+00:00"},
            {"title": "Amichevole", "starts_at": "2026-10-05T20:00:00+00:00"},
        ])
        self.assertTrue(msg["title"].startswith("⚽ Stasera alle 21:00: Allenamento"))
        self.assertIn("+1 altri eventi", msg["title"])
        self.assertEqual(msg["route"], "/presenze")


class SupabaseTest(unittest.TestCase):
    def test_user_agent_non_da_browser(self):
        db = notify.Supabase("https://x.supabase.co", "sb_secret_test")
        self.assertNotIn("mozilla", db.headers["User-Agent"].lower())


class NovitaTest(unittest.TestCase):
    def test_invia_e_segna_come_notificati(self):
        db = FakeDb({
            "news": [{"id": 7, "title": "TU 1.0.5", "published_at": "2026-10-03T08:00:00+00:00"}],
            "events": [{"id": "e1", "type": "allenamento", "title": "Schemi",
                        "starts_at": "2026-10-06T19:00:00+00:00"}],
        })
        sent = []
        notify.run_novita(db, sent.append)
        self.assertEqual(len(sent), 2)
        self.assertEqual(db.marked, {"news": [7], "events": ["e1"]})


class PromemoriaTest(unittest.TestCase):
    def test_solo_eventi_non_ancora_iniziati(self):
        now = datetime(2026, 10, 5, 14, 0, tzinfo=timezone.utc)
        db = FakeDb({"events": [
            {"id": 1, "title": "Mattina", "starts_at": "2026-10-05T08:00:00+00:00"},
            {"id": 2, "title": "Sera", "starts_at": "2026-10-05T19:30:00+00:00"},
        ]})
        events = notify.todays_events(db, now)
        self.assertEqual([e["title"] for e in events], ["Sera"])
        query = db.queries[0][1]
        self.assertIn("2026-10-05T00:00:00+02:00", query["and"])


if __name__ == "__main__":
    unittest.main()
