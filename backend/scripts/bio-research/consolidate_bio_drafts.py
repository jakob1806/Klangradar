#!/usr/bin/env python3
"""Verdichtet bio_research_results.jsonl (Ausgabe von research_all_bios.py)
auf einen aktuellen Datensatz pro Entität, reichert um einen Wikipedia-
Zusatzcheck an und exportiert CSV/JSONL für den externen Redaktions-Review
(z.B. per Hand oder per Upload in ein LLM-Chat-Tool).

Ältere, verworfene Ergebnisse für dieselbe Entität landen NICHT im Nichts,
sondern in einer separaten Historie-Datei (--history-output).

WICHTIGER BUGFIX gegenüber der Vorversion (build_claude_bio_package.py):
die alte Fassung wählte den LÄNGEREN von Bestandstext/KI-Entwurf als
"proposed"-Text aus (`proposed = draft if len(draft) >= len(current) else
current`) — genau der Anti-Pattern, den die Bio-Recherche-Anforderung
("wähle nicht automatisch den längeren Text als besseren Text") ausdrücklich
verbietet. Bestandstext und KI-Entwurf werden jetzt durchgehend als zwei
GETRENNTE Spalten exportiert; welcher Text übernommen wird, entscheidet
ausschließlich die Redaktion.

Der Wikipedia-Zusatzcheck vergleicht zusätzlich zum Namens-String-Abgleich
das im Artikel genannte Geburts-/Sterbejahr (falls vorhanden) gegen das in
der Datenbank hinterlegte birth_date/death_date — ein klarer Widerspruch
setzt die Konfidenz unabhängig von der Namensähnlichkeit auf "niedrig"
(gleiches Prinzip wie der deterministische Gegencheck in
backend/supabase/functions/_shared/bioResearch.ts).
"""

import argparse
import csv
import difflib
import json
import logging
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

logger = logging.getLogger("consolidate_bio_drafts")

PAGE_SIZE = 1000
WIKI_AGENT = "KlassikMuenchenBot/1.0 (https://klassik-muenchen.de)"
BIRTH_YEAR_PATTERN = re.compile(r"(?:\*|geb\.?|geboren(?:\s+am)?)\s*(?:\d{1,2}\.\s*\w+\s+)?(\d{4})", re.IGNORECASE)
DEATH_YEAR_PATTERN = re.compile(r"(?:†|gest\.?|gestorben(?:\s+am)?)\s*(?:\d{1,2}\.\s*\w+\s+)?(\d{4})", re.IGNORECASE)


def load_env(env_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if env_path.exists():
        for raw in env_path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                values[k] = v.strip().strip("'\"")
    values.update({k: v for k, v in os.environ.items() if k in ("NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY")})
    return values


def fetch_all_rows(base: str, headers: dict[str, str], table: str, select: str, order: str) -> list[dict]:
    rows: list[dict] = []
    offset = 0
    while True:
        params = urllib.parse.urlencode({"select": select, "order": f"{order}.asc", "limit": str(PAGE_SIZE), "offset": str(offset)})
        request = urllib.request.Request(f"{base}/rest/v1/{table}?{params}", headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            page = json.load(response)
        if not page:
            break
        rows.extend(page)
        if len(page) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    return rows


def collect_entities(base: str, headers: dict[str, str]) -> list[dict]:
    entities: list[dict] = []
    for row in fetch_all_rows(base, headers, "venues", "id,name,description_de,venue_type,district,address_city,capacity", "name"):
        entities.append({
            "entity_type": "venue", "entity_id": row["id"], "name": row["name"],
            "current_text": row.get("description_de") or "",
            "context": ", ".join(str(v) for v in (row.get("venue_type"), row.get("district"), row.get("address_city")) if v),
            "birth_year": None, "death_year": None,
        })
    for row in fetch_all_rows(base, headers, "persons", "id,full_name,biography_de,roles,instrument,nationality,birth_date,death_date", "full_name"):
        context_parts = list(row.get("roles") or [])
        context_parts.extend(str(v) for v in (row.get("instrument"), row.get("nationality")) if v)
        entities.append({
            "entity_type": "person", "entity_id": row["id"], "name": row["full_name"],
            "current_text": row.get("biography_de") or "", "context": ", ".join(context_parts),
            "birth_year": _year_of(row.get("birth_date")), "death_year": _year_of(row.get("death_date")),
        })
    for row in fetch_all_rows(base, headers, "ensembles", "id,name,description_de,type,founded_year,member_count", "name"):
        entities.append({
            "entity_type": "ensemble", "entity_id": row["id"], "name": row["name"],
            "current_text": row.get("description_de") or "",
            "context": ", ".join(str(v) for v in (row.get("type"), row.get("founded_year"), row.get("member_count")) if v),
            "birth_year": None, "death_year": None,
        })
    return entities


def _year_of(date_str) -> int | None:
    if not isinstance(date_str, str) or len(date_str) < 4:
        return None
    try:
        return int(date_str[:4])
    except ValueError:
        return None


def normalized(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.casefold().replace("ß", "ss"))


def _contradicts_year(text: str, known_year: int | None, pattern: re.Pattern) -> bool:
    if not known_year:
        return False
    mentioned = [int(m.group(1)) for m in pattern.finditer(text)]
    return bool(mentioned) and known_year not in mentioned


def wiki_search(entity: dict) -> tuple[dict, dict]:
    params = urllib.parse.urlencode({
        "action": "query", "generator": "search", "gsrsearch": entity["name"], "gsrlimit": 1,
        "prop": "extracts", "exintro": 1, "explaintext": 1, "format": "json", "origin": "*",
    })
    request = urllib.request.Request(f"https://de.wikipedia.org/w/api.php?{params}", headers={"User-Agent": WIKI_AGENT})
    try:
        payload = None
        for attempt in range(3):
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    payload = json.load(response)
                break
            except urllib.error.URLError:
                if attempt == 2:
                    raise
                time.sleep(1 + attempt)
        pages = (payload or {}).get("query", {}).get("pages", {})
        if not pages:
            return entity, {}
        page = next(iter(pages.values()))
        title = page.get("title", "")
        extract = re.sub(r"\s+", " ", page.get("extract", "")).strip()
        name_norm, title_norm = normalized(entity["name"]), normalized(title)
        ratio = difflib.SequenceMatcher(None, name_norm, title_norm).ratio() if name_norm and title_norm else 0
        name_matches = name_norm == title_norm or name_norm in title_norm or title_norm in name_norm
        confidence = "hoch" if name_matches else "mittel" if ratio >= 0.72 else "niedrig"

        # Deterministischer Gegencheck: ein klar abweichendes Geburts-/
        # Sterbejahr überstimmt den Namens-Abgleich — siehe Datei-Kommentar.
        if _contradicts_year(extract, entity.get("birth_year"), BIRTH_YEAR_PATTERN) or _contradicts_year(
            extract, entity.get("death_year"), DEATH_YEAR_PATTERN,
        ):
            confidence = "niedrig"

        excerpt_words = extract.split()[:20]
        return entity, {
            "wikipedia_title": title,
            "wikipedia_url": f"https://de.wikipedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}",
            "source_excerpt": " ".join(excerpt_words) + ("…" if len(extract.split()) > 20 else ""),
            "match_confidence": confidence,
        }
    except Exception as exc:  # noqa: BLE001 - best-effort research helper, never fatal
        logger.debug("Wikipedia-Suche für %r fehlgeschlagen: %s", entity["name"], exc)
        return entity, {}


def load_latest_drafts(raw_results_path: Path, history_path: Path) -> dict[tuple[str, str], dict]:
    """Liest bio_research_results.jsonl, behält pro Entität NUR den neuesten
    Eintrag (letzte Zeile gewinnt — research_all_bios.py hängt chronologisch
    an), und schreibt alle verworfenen älteren Einträge nach history_path
    statt sie stillschweigend zu verwerfen."""
    latest: dict[tuple[str, str], dict] = {}
    superseded: list[dict] = []
    if raw_results_path.exists():
        for line in raw_results_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            key = (row["entity_type"], row["entity_id"])
            if key in latest:
                superseded.append(latest[key])
            latest[key] = row
    if superseded:
        with history_path.open("a", encoding="utf-8") as handle:
            for row in superseded:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
        logger.info("%d ältere Recherche-Ergebnisse nach %s verschoben", len(superseded), history_path)
    return latest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env-file", type=Path, default=None)
    parser.add_argument("--raw-results", type=Path, default=None, help="bio_research_results.jsonl (Default: <script-dir>/bio_research_results.jsonl)")
    parser.add_argument("--history-output", type=Path, default=None, help="Zieldatei für verworfene ältere Recherche-Ergebnisse (Default: <script-dir>/bio_research_results.history.jsonl)")
    parser.add_argument("--csv-output", type=Path, default=None)
    parser.add_argument("--jsonl-output", type=Path, default=None)
    parser.add_argument("--skip-wikipedia", action="store_true", help="Wikipedia-Zusatzsuche überspringen (schneller, aber ohne Quellenhinweis/Konfidenz)")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parents[2]
    env_path = args.env_file or (repo_root / "admin" / ".env.local")
    raw_results_path = args.raw_results or (script_dir / "bio_research_results.jsonl")
    history_path = args.history_output or (script_dir / "bio_research_results.history.jsonl")
    csv_path = args.csv_output or (script_dir / "Biografien_fuer_Claude.csv")
    jsonl_path = args.jsonl_output or (script_dir / "Biografien_fuer_Claude.jsonl")

    env = load_env(env_path)
    base = env.get("NEXT_PUBLIC_SUPABASE_URL", "").rstrip("/")
    key = env.get("NEXT_PUBLIC_SUPABASE_ANON_KEY", "")
    if not base or not key:
        logger.error("NEXT_PUBLIC_SUPABASE_URL/NEXT_PUBLIC_SUPABASE_ANON_KEY fehlen (gesucht in %s)", env_path)
        return 2
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}

    logger.info("Lade Entitäten ...")
    entities = collect_entities(base, headers)
    latest_drafts = load_latest_drafts(raw_results_path, history_path)

    wiki_results: dict[tuple[str, str], dict] = {}
    if not args.skip_wikipedia:
        logger.info("Wikipedia-Zusatzsuche für %d Entitäten ...", len(entities))
        import concurrent.futures as cf
        with cf.ThreadPoolExecutor(max_workers=2) as executor:
            for entity, result in executor.map(wiki_search, entities):
                wiki_results[(entity["entity_type"], entity["entity_id"])] = result

    labels = {"venue": "Veranstaltungsort", "person": "Person", "ensemble": "Ensemble"}
    records = []
    for entity in entities:
        key_tuple = (entity["entity_type"], entity["entity_id"])
        draft_row = latest_drafts.get(key_tuple, {})
        draft_text = (draft_row.get("draft_text") or "").strip()
        current_text = entity["current_text"].strip()
        wiki = wiki_results.get(key_tuple, {})

        # Status beruht auf VORHANDENSEIN, nicht auf Textlänge — siehe
        # Datei-Kommentar zum Bugfix.
        if draft_text:
            status = "KI-Entwurf vorhanden – redaktionell prüfen"
        elif current_text:
            status = "Bestandstext vorhanden – ggf. ergänzen"
        elif wiki.get("wikipedia_url") and wiki.get("match_confidence") != "niedrig":
            status = "Quelle vorhanden – auszuarbeiten"
        else:
            status = "Keine Quelle gefunden – manuelle Recherche nötig"

        records.append({
            "kategorie": labels[entity["entity_type"]],
            "typ": entity["entity_type"],
            "id": entity["entity_id"],
            "name": entity["name"],
            "kontext": entity["context"],
            "bestandstext": current_text,
            "ki_entwurf": draft_text,
            "ki_entwurf_quelle": draft_row.get("source_type", ""),
            "wikipedia_titel": wiki.get("wikipedia_title", ""),
            "wikipedia_url": wiki.get("wikipedia_url", ""),
            "wikipedia_auszug": wiki.get("source_excerpt", ""),
            "wikipedia_konfidenz": wiki.get("match_confidence", ""),
            "status": status,
        })

    fieldnames = list(records[0].keys()) if records else []
    with csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)
    with jsonl_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")

    logger.info("%d Datensätze exportiert nach %s und %s", len(records), csv_path, jsonl_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
