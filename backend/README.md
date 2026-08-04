# backend

Supabase-Projekt (Postgres + Deno-Edge-Functions) für KoKal/Klassik München —
Datenmodell, Ingestion-Pipeline, Anreicherungs-Functions.

## Struktur

- `supabase/migrations/` — datumsbasiert benannte SQL-Migrationen, einzige
  Quelle der Wahrheit für das Schema.
- `supabase/functions/` — Deno-Edge-Functions, eine pro Verzeichnis.
  `_shared/` enthält wiederverwendete Module (KI-Provider-Router,
  Bild-Pipeline, robots.txt-Check, Provenienz-Tracking, ...) — kein
  gemeinsamer Modul-Raum zwischen einzelnen Functions, deshalb werden
  manche kleinen Hilfsfunktionen (z.B. `slugify()`) pro Function dupliziert
  statt gemeinsam importiert.
- `scripts/` — CLI-Skripte, die Edge Functions von außen aufrufen (Batch-
  Läufe, manuelle Nachläufe) oder direkt gegen die REST-API schreiben.
  `scripts/bio-research/` ist ein eigenständiges Python/Node-Toolset mit
  eigener README für die Biografie-Recherche-Pipeline.
- `ingestion/` — Rohdaten/Konfiguration für die Quellen-Ingestion.

## Wichtigste Functions

- `ingest-source` — holt/parst eine einzelne Quelle (schema_org/ical/rss/
  scrape/api/brso), dedupliziert per `(source_id, external_id)` bzw.
  Fuzzy-Match, schreibt/aktualisiert `events`.
- `run-all-sources` — Cron-Orchestrator, ruft `ingest-source` für alle
  fälligen aktiven Quellen auf (begrenzte Nebenläufigkeit).
- `enrich-*` — Anreicherungs-Functions pro Datenbereich (Personen-/
  Ensemble-/Venue-Profile, Event-Referenzen/Programm, Preise, Bilder).
- `research-entity-bio` — recherchiert eine Biografie/Beschreibung, speichert
  aber nichts selbst (Redaktion entscheidet vor dem Übernehmen).
- `resolve-person-duplicates` / `resolve-entity-candidates` — Namensvarianten-
  Erkennung bzw. Kandidaten-Nachlauf; beide legen KI-Funde zur redaktionellen
  Prüfung vor, kein automatischer Merge/keine automatische Löschung.

## Lokale Entwicklung

```bash
cp .env.example .env   # Werte eintragen, NIE committen
supabase functions serve --env-file .env
```

Setzt Docker Desktop voraus (lokale Postgres-Instanz).

## Tests

```bash
deno test supabase/functions/_shared/**/*.test.ts
deno check supabase/functions/<function>/index.ts
deno lint supabase/functions/<function>/index.ts
```

## Deploy

Migrationen und Functions deployen über die bestehenden GitHub-Actions-
Workflows (`.github/workflows/deploy-migrations.yml`,
`deploy-edge-functions.yml`) bei Merge nach `main`. Für einen gezielten
manuellen Deploy während der Entwicklung:

```bash
supabase db push --linked
supabase functions deploy <function> --project-ref <ref>
```
