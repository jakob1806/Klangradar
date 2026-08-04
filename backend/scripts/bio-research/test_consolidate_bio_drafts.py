"""Tests fuer consolidate_bio_drafts.py (Abschnitt 9 der Gesamtueberarbeitung:
"Tests fuer Recherche-Ergebnis-Konsolidierung"). Reine stdlib unittest, kein
zusaetzliches Test-Framework noetig - deckt genau die drei Punkte ab, die
diese Datei laut eigenem Docstring gegenueber der Vorversion
(build_claude_bio_package.py) korrigiert: kein "laengerer Text gewinnt",
Jahres-Gegencheck bei Wikipedia-Treffern, Historie statt stillem Ueberschreiben.

Ausfuehren: python3 -m unittest test_consolidate_bio_drafts.py -v
"""
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from consolidate_bio_drafts import (
    BIRTH_YEAR_PATTERN,
    DEATH_YEAR_PATTERN,
    _contradicts_year,
    _year_of,
    derive_status,
    load_latest_drafts,
    normalized,
)


class DeriveStatusTests(unittest.TestCase):
    def test_draft_present_wins_regardless_of_length_vs_current(self):
        # Der eigentliche Bugfix: ein kurzer KI-Entwurf schlaegt einen viel
        # laengeren Bestandstext nicht laenger automatisch - Vorhandensein
        # entscheidet, nicht Laenge.
        status = derive_status("Kurz.", "Ein sehr viel laengerer Bestandstext " * 20, {})
        self.assertEqual(status, "KI-Entwurf vorhanden – redaktionell prüfen")

    def test_current_only_when_no_draft(self):
        status = derive_status("", "Bestandstext.", {})
        self.assertEqual(status, "Bestandstext vorhanden – ggf. ergänzen")

    def test_wiki_source_when_no_texts_and_confidence_not_low(self):
        status = derive_status("", "", {"wikipedia_url": "https://de.wikipedia.org/wiki/X", "match_confidence": "hoch"})
        self.assertEqual(status, "Quelle vorhanden – auszuarbeiten")

    def test_low_confidence_wiki_hit_does_not_count_as_a_usable_source(self):
        status = derive_status("", "", {"wikipedia_url": "https://de.wikipedia.org/wiki/X", "match_confidence": "niedrig"})
        self.assertEqual(status, "Keine Quelle gefunden – manuelle Recherche nötig")

    def test_nothing_found(self):
        status = derive_status("", "", {})
        self.assertEqual(status, "Keine Quelle gefunden – manuelle Recherche nötig")


class YearContradictionTests(unittest.TestCase):
    def test_no_known_year_never_contradicts(self):
        self.assertFalse(_contradicts_year("geboren 1900", None, BIRTH_YEAR_PATTERN))

    def test_matching_year_does_not_contradict(self):
        self.assertFalse(_contradicts_year("geb. 1985 in Muenchen", 1985, BIRTH_YEAR_PATTERN))

    def test_different_year_contradicts(self):
        self.assertTrue(_contradicts_year("geb. 1950 in Muenchen", 1985, BIRTH_YEAR_PATTERN))

    def test_no_year_mentioned_is_not_treated_as_a_contradiction(self):
        # Fehlen einer Jahresangabe im Wikipedia-Auszug ist kein Widerspruch,
        # nur ein davon abweichend genanntes Jahr ist einer.
        self.assertFalse(_contradicts_year("Ein Text ohne Jahresangabe.", 1985, BIRTH_YEAR_PATTERN))

    def test_death_year_pattern_independent_of_birth_pattern(self):
        self.assertTrue(_contradicts_year("gestorben 1999", 2005, DEATH_YEAR_PATTERN))
        self.assertFalse(_contradicts_year("gestorben 2005", 2005, DEATH_YEAR_PATTERN))


class YearOfTests(unittest.TestCase):
    def test_parses_leading_year(self):
        self.assertEqual(_year_of("1985-03-12"), 1985)

    def test_none_for_missing_or_short_value(self):
        self.assertIsNone(_year_of(None))
        self.assertIsNone(_year_of("19"))

    def test_none_for_non_numeric_prefix(self):
        self.assertIsNone(_year_of("abcd-03-12"))


class NormalizedTests(unittest.TestCase):
    def test_folds_case_and_strips_punctuation(self):
        self.assertEqual(normalized("J.S. Bach"), "jsbach")

    def test_folds_sharp_s(self):
        self.assertEqual(normalized("Straße"), "strasse")


class LoadLatestDraftsTests(unittest.TestCase):
    def test_keeps_only_the_last_entry_per_entity_and_preserves_older_ones_in_history(self):
        with TemporaryDirectory() as tmp:
            raw_path = Path(tmp) / "bio_research_results.jsonl"
            history_path = Path(tmp) / "bio_research_results.history.jsonl"
            rows = [
                {"entity_type": "person", "entity_id": "p1", "draft_text": "alter Entwurf"},
                {"entity_type": "person", "entity_id": "p1", "draft_text": "neuer Entwurf"},
                {"entity_type": "venue", "entity_id": "v1", "draft_text": "einziger Entwurf"},
            ]
            raw_path.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")

            latest = load_latest_drafts(raw_path, history_path)

            self.assertEqual(latest[("person", "p1")]["draft_text"], "neuer Entwurf")
            self.assertEqual(latest[("venue", "v1")]["draft_text"], "einziger Entwurf")
            self.assertTrue(history_path.exists())
            history_rows = [json.loads(line) for line in history_path.read_text(encoding="utf-8").splitlines()]
            self.assertEqual(len(history_rows), 1)
            self.assertEqual(history_rows[0]["draft_text"], "alter Entwurf")

    def test_missing_raw_results_file_returns_empty_without_error(self):
        with TemporaryDirectory() as tmp:
            latest = load_latest_drafts(Path(tmp) / "does-not-exist.jsonl", Path(tmp) / "history.jsonl")
            self.assertEqual(latest, {})


if __name__ == "__main__":
    unittest.main()
