import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fetch_news as fn  # noqa: E402

FIXTURES = Path(__file__).with_name("fixtures")
NOW = datetime(2026, 10, 3, 12, tzinfo=timezone.utc)


def load(name, source):
    items = fn.parse_feed((FIXTURES / name).read_text(encoding="utf-8"), source)
    return fn.select(items, source, NOW)


class GoogleNewsTest(unittest.TestCase):
    source = {"name": "GN", "category": "aggiornamenti", "require": ["fc 27"]}

    def test_filtra_e_pulisce(self):
        items = load("google_news.xml", self.source)
        titles = [i.title for i in items]
        self.assertIn("EA Sports FC 27, disponibile il Title Update 1.0.4: tutte le novità", titles)
        self.assertFalse(any("Calciomercato" in t for t in titles))  # non pertinente

    def test_testata_e_descrizione(self):
        item = load("google_news.xml", self.source)[0]
        self.assertEqual(item.source, "Everyeye.it")
        self.assertEqual(item.summary, "Leggi l'articolo completo su Everyeye.it.")
        self.assertEqual(item.category, "aggiornamenti")

    def test_classificazione_ultimate_team(self):
        items = {i.source: i for i in load("google_news.xml", self.source)}
        self.assertEqual(items["FUTBIN"].category, "ultimate_team")


class WordpressTest(unittest.TestCase):
    source = {"name": "FUT.it", "category": "ultimate_team"}

    def test_riassunto_breve_e_immagine(self):
        items = load("wordpress.xml", self.source)
        self.assertEqual(len(items), 1)  # la notizia di giugno è troppo vecchia
        item = items[0]
        self.assertLessEqual(len(item.summary), fn.SUMMARY_MAX + 1)
        self.assertTrue(item.summary.startswith("Disponibile da oggi la nuova Evoluzione"))
        self.assertNotIn("<", item.summary)
        self.assertEqual(item.image_url, "https://fifaultimateteam.it/wp-content/uploads/ala.jpg")
        self.assertEqual(item.source, "FUT.it")


class FeedMalformatoTest(unittest.TestCase):
    def test_rss_con_attributi_duplicati(self):
        items = load("wordpress_broken.xml", {"name": "FUT.it", "category": "ultimate_team"})
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].title, "FC 27: nuove SBC & evoluzioni del weekend")
        self.assertEqual(items[0].summary, "Tutte le SBC disponibili da oggi.")
        self.assertEqual(items[0].image_url, "https://fifaultimateteam.it/img.jpg")


class AtomTest(unittest.TestCase):
    def test_reddit(self):
        items = load("reddit_atom.xml", {"name": "Reddit", "category": "pro_clubs", "max_items": 5})
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].url, "https://www.reddit.com/r/FIFAProClubs/comments/abc/best_build/")
        self.assertEqual(items[0].category, "aggiornamenti")  # "patch" nel titolo
        self.assertEqual(items[0].image_url, "https://b.thumbs.redditmedia.com/x.jpg")


class ConsoleTest(unittest.TestCase):
    def test_console_resta_console_con_piattaforma(self):
        now = datetime.now(timezone.utc)
        source = {"name": "GN PS5", "category": "console", "require": ["aggiornamento di sistema"]}
        ps5 = fn.NewsItem(source="GN", category="console", title="PS5: aggiornamento di sistema 10.02",
                          summary="Nuovo firmware per PlayStation 5", url="https://x.it/ps5",
                          published_at=now.isoformat())
        xbox = fn.NewsItem(source="GN", category="console", title="Xbox, aggiornamento di sistema di ottobre",
                           summary="", url="https://x.it/xbox", published_at=now.isoformat())
        fuori = fn.NewsItem(source="GN", category="console", title="Nuovo controller in vendita",
                            summary="", url="https://x.it/pad", published_at=now.isoformat())
        items = {i.url: i for i in fn.select([ps5, xbox, fuori], source, now)}
        self.assertEqual(set(items), {"https://x.it/ps5", "https://x.it/xbox"})
        self.assertEqual(items["https://x.it/ps5"].category, "console")  # non "aggiornamenti"
        self.assertEqual(items["https://x.it/ps5"].platform, "ps5")
        self.assertEqual(items["https://x.it/xbox"].platform, "xbox")


class SupabaseTest(unittest.TestCase):
    def test_user_agent_non_da_browser(self):
        # Le chiavi sb_secret_ vengono rifiutate (401) con un User-Agent da browser.
        db = fn.Supabase("https://x.supabase.co", "sb_secret_test")
        self.assertNotIn("mozilla", db.headers["User-Agent"].lower())


class SourcesTest(unittest.TestCase):
    def test_file_fonti_valido(self):
        sources = fn.load_sources(Path(fn.__file__).with_name("sources.json"))
        categories = {"tornei", "aggiornamenti", "ultimate_team", "pro_clubs", "console"}
        for s in sources:
            self.assertIn(s["category"], categories, s["name"])
            self.assertTrue(s["url"].startswith("https://"), s["name"])


if __name__ == "__main__":
    unittest.main()
