#!/usr/bin/env python3
"""Ruft die research-entity-bio Edge Function für alle Venues/Personen/
Ensembles ohne (oder mit sehr kurzer) Biografie/Beschreibung auf und schreibt
jedes Ergebnis als eine JSONL-Zeile weg.

HINWEIS: Der eigentliche, aktuelle Redaktions-Workflow für Bio-Recherche ist
die interaktive Seite /bio-research im Admin-Dashboard (ruft dieselbe
Edge Function auf, ein Eintrag nach dem anderen, mit Bearbeiten-vor-
Übernehmen) bzw. backend/scripts/research-missing-person-bios.mjs für einen
automatisierten Batch mit klarer Speicher-Policy (nur "wikipedia"-Quellen
werden automatisch übernommen). Dieses Skript ist der Batch-RECHERCHE-Schritt
für den älteren Word/Excel-Export-Workflow (siehe build_claude_bio_package.py)
— es schreibt NIE in die Datenbank, nur in bio_research_results.jsonl.

Nutzt Paginierung (statt eines einzelnen limit=1000-Aufrufs) — bei Tabellen
mit mehr als 1000 Zeilen würde ein fester Limit-Wert ohne Paginierung
stillschweigend den Rest verlieren.
"""

import argparse
import concurrent.futures
import json
import logging
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

logger = logging.getLogger("research_all_bios")

PAGE_SIZE = 1000
MIN_DRAFT_CHARACTERS = 300


def load_env(env_path: Path) -> dict[str, str]:
    """Lädt KEY=VALUE-Zeilen aus einer .env-Datei, überschreibt aber nicht
    bereits gesetzte echte Umgebungsvariablen (os.environ hat Vorrang)."""
    values: dict[str, str] = {}
    if env_path.exists():
        for raw in env_path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key] = value.strip().strip("'\"")
    values.update({k: v for k, v in os.environ.items() if k in ("NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY")})
    return values


def fetch_all_rows(base: str, headers: dict[str, str], table: str, select: str, order: str) -> list[dict]:
    """Holt ALLE Zeilen einer Tabelle über Offset-Paginierung (PAGE_SIZE pro
    Anfrage) statt eines einzelnen limit-Aufrufs, der bei > PAGE_SIZE Zeilen
    den Rest still verlieren würde."""
    rows: list[dict] = []
    offset = 0
    while True:
        params = urllib.parse.urlencode({
            "select": select,
            "order": f"{order}.asc",
            "limit": str(PAGE_SIZE),
            "offset": str(offset),
        })
        request = urllib.request.Request(f"{base}/rest/v1/{table}?{params}", headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                page = json.load(response)
        except urllib.error.HTTPError as exc:
            logger.error("Abruf von %s (offset=%d) fehlgeschlagen: HTTP %s", table, offset, exc.code)
            raise
        if not page:
            break
        rows.extend(page)
        if len(page) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    return rows


def fetch_entities(base: str, headers: dict[str, str], entity_type: str, table: str, name_column: str, bio_column: str) -> list[dict]:
    rows = fetch_all_rows(base, headers, table, f"id,{name_column},{bio_column}", name_column)
    return [
        {
            "entity_type": entity_type,
            "entity_id": row["id"],
            "name": row[name_column],
            "current_text": row.get(bio_column) or "",
        }
        for row in rows
    ]


def research_one(base: str, headers: dict[str, str], row: dict, retries: int, timeout: float) -> dict:
    payload = json.dumps({"entityType": row["entity_type"], "entityId": row["entity_id"]}).encode()
    request = urllib.request.Request(
        f"{base}/functions/v1/research-entity-bio",
        data=payload,
        method="POST",
        headers={**headers, "Content-Type": "application/json"},
    )
    last_error = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                result = json.load(response)
            draft = (result.get("biography") or "").strip()
            return {
                **row,
                "draft_text": draft,
                "source_type": result.get("source") or "",
                "source_url": result.get("sourceUrl") or "",
                "found": bool(result.get("found") and draft),
                "error": "",
            }
        except Exception as exc:  # noqa: BLE001 - retried below, logged on final failure
            last_error = str(exc)
            if attempt < retries - 1:
                time.sleep(2 ** attempt)
    return {
        **row,
        "draft_text": "",
        "source_type": "",
        "source_url": "",
        "found": False,
        "error": last_error or "Unbekannter Fehler",
    }


def load_previous_results(output_path: Path) -> dict[tuple[str, str], dict]:
    done: dict[tuple[str, str], dict] = {}
    if output_path.exists():
        for line in output_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                item = json.loads(line)
                done[(item["entity_type"], item["entity_id"])] = item
    return done


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env-file", type=Path, default=None, help="Pfad zu einer .env-Datei mit NEXT_PUBLIC_SUPABASE_URL/_ANON_KEY (Default: admin/.env.local relativ zum Repo-Root)")
    parser.add_argument("--output", type=Path, default=None, help="Zieldatei für die JSONL-Ergebnisse (Default: <script-dir>/bio_research_results.jsonl)")
    parser.add_argument("--max-workers", type=int, default=2, help="Parallele Recherche-Anfragen (Default: 2 — die Edge Function ruft ihrerseits Wikipedia + ggf. ein KI-Modell auf, zu hohe Parallelität riskiert Rate-Limits)")
    parser.add_argument("--min-draft-characters", type=int, default=MIN_DRAFT_CHARACTERS, help="Ab dieser Zeichenzahl gilt ein vorhandener Entwurf als 'erledigt' und wird nicht erneut recherchiert")
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=75.0)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parents[2]  # backend/scripts/bio-research -> repo root
    env_path = args.env_file or (repo_root / "admin" / ".env.local")
    output_path = args.output or (script_dir / "bio_research_results.jsonl")

    env = load_env(env_path)
    base = env.get("NEXT_PUBLIC_SUPABASE_URL", "").rstrip("/")
    key = env.get("NEXT_PUBLIC_SUPABASE_ANON_KEY", "")
    if not base or not key:
        logger.error("NEXT_PUBLIC_SUPABASE_URL/NEXT_PUBLIC_SUPABASE_ANON_KEY fehlen (gesucht in %s und der Umgebung)", env_path)
        return 2
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}

    logger.info("Lade Entitäten von %s ...", base)
    rows: list[dict] = []
    rows.extend(fetch_entities(base, headers, "venue", "venues", "name", "description_de"))
    rows.extend(fetch_entities(base, headers, "person", "persons", "full_name", "biography_de"))
    rows.extend(fetch_entities(base, headers, "ensemble", "ensembles", "name", "description_de"))

    done = load_previous_results(output_path)
    pending = [row for row in rows if done.get((row["entity_type"], row["entity_id"]), {}).get("draft_characters", 0) < args.min_draft_characters]
    logger.info("Gesamt: %d, bereits erledigt: %d, ausstehend: %d", len(rows), len(rows) - len(pending), len(pending))

    write_lock = threading.Lock()
    completed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        futures = {executor.submit(research_one, base, headers, row, args.retries, args.timeout): row for row in pending}
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            result["draft_characters"] = len(result["draft_text"])
            result["current_characters"] = len(result["current_text"].strip())
            with write_lock:
                with output_path.open("a", encoding="utf-8") as handle:
                    handle.write(json.dumps(result, ensure_ascii=False) + "\n")
            completed += 1
            if completed % 10 == 0 or completed == len(pending):
                logger.info(
                    "%d/%d verarbeitet — zuletzt: %s (gefunden=%s, %d Zeichen)",
                    completed, len(pending), result["name"], result["found"], result["draft_characters"],
                )

    logger.info("Fertig. Ergebnisse in %s", output_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
