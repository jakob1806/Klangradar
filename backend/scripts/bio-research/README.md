# Bio-Research-Skripte

Werkzeuge rund um die Recherche fehlender Biografien/Beschreibungen für
Venues, Personen und Ensembles. **Der aktuelle, empfohlene Workflow ist die
interaktive Seite `/bio-research` im Admin-Dashboard** (eine Entität nach der
anderen, Entwurf vor dem Übernehmen bearbeitbar, nie automatisches
Speichern) bzw. für einen automatisierten Batch
[`../research-missing-person-bios.mjs`](../research-missing-person-bios.mjs)
(speichert nur "wikipedia"-Quellen automatisch, alles andere bleibt zur
manuellen Prüfung offen).

Die Skripte in diesem Ordner sind ein **älterer, ergänzender Weg**: sie
exportieren eine Referenz-Übersicht (Word/Excel/CSV) für externe Bearbeitung
(z. B. Hochladen in ein LLM-Chat-Tool) statt einer interaktiven Web-Seite.
Sie schreiben **nie** direkt in die Datenbank — jeder erzeugte Text muss über
`/bio-research` oder eine eigene, manuelle Aktualisierung übernommen werden.

## Voraussetzungen

```bash
pip install -r requirements.txt
npm install
```

Eine `.env.local`-Datei mit `NEXT_PUBLIC_SUPABASE_URL`/`NEXT_PUBLIC_SUPABASE_ANON_KEY`
wird benötigt — Standardmäßig wird `admin/.env.local` im Repo-Root gesucht,
alternativ per `--env-file`. Siehe `.env.example`.

## Ablauf

1. **`research_all_bios.py`** — ruft `research-entity-bio` für alle Venues/
   Personen/Ensembles ohne (ausreichend langen) Text auf, schreibt jedes
   Ergebnis als JSONL-Zeile nach `bio_research_results.jsonl`. Wiederholt
   ausführbar (überspringt bereits erledigte Einträge).

   ```bash
   python3 research_all_bios.py --verbose
   ```

2. **`consolidate_bio_drafts.py`** — verdichtet `bio_research_results.jsonl`
   auf einen aktuellen Datensatz pro Entität (ältere Ergebnisse wandern nach
   `bio_research_results.history.jsonl`, statt verloren zu gehen), ergänzt
   eine zusätzliche Wikipedia-Suche mit Geburts-/Sterbejahr-Gegencheck, und
   exportiert `Biografien_fuer_Claude.csv`/`.jsonl`.

   **Wichtig:** Bestandstext (`bestandstext`) und KI-Entwurf (`ki_entwurf`)
   bleiben immer getrennte Spalten — es gibt keine automatische
   "längerer Text gewinnt"-Auswahl (das war ein Bug in der Vorversion,
   `build_claude_bio_package.py`, siehe Git-Historie).

   ```bash
   python3 consolidate_bio_drafts.py --verbose
   ```

3. **`build_bio_workbook.mjs`** — baut aus dem JSONL-Export eine formatierte
   Excel-Arbeitsmappe (Anleitung + je eine Tabelle für Alle/Venues/Personen/
   Ensembles, mit einer leeren "Finaler Text"-Spalte zum Ausfüllen).

   ```bash
   node build_bio_workbook.mjs --out-dir outputs/bio_import_$(date +%F)
   ```

4. **`build_missing_bios_doc.py`** / **`build_missing_images_doc.py`** —
   erzeugen jeweils eine reine Word-Referenzliste (Namen ohne Text bzw. ohne
   Bild), unabhängig vom obigen Recherche-Ablauf.

   ```bash
   python3 build_missing_bios_doc.py
   python3 build_missing_images_doc.py
   ```

## Historie / bekannte Einschränkungen

- `verify_bio_workbook.mjs` (PNG-Vorschau-Rendering der Arbeitsmappe) wurde
  **nicht** portiert — das nutzte ein Codex-CLI-internes Paket
  (`@oai/artifact-tool`) ohne öffentliches Äquivalent. Zur Sichtprüfung die
  erzeugte `.xlsx` einfach direkt öffnen.
- `_archive/` enthält QA-Zwischenstände einer früheren Iteration (Word-Layout-
  Prüfläufe) — rein historisch, nicht Teil des aktiven Workflows.
- Alle Skripte nutzen Offset-Paginierung gegen Supabase (nicht einen
  einzelnen `limit=1000`-Aufruf) — bei > 1000 Zeilen in einer Tabelle würde
  ein fester Limit-Wert sonst den Rest still verlieren.
