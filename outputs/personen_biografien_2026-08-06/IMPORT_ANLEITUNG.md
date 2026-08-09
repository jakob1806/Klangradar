# Personen-Biografien – Importanleitung

Stand: 6. August 2026. Die produktive Datenbank wurde bei der Erstellung dieses Pakets nicht verändert.

## Dateien

- `personen_biografien_import.jsonl`: 189 geprüfte, direkt importierbare Biografien.
- `personen_biografien_mit_pruefung.jsonl`: zusätzlich 156 fertige Entwürfe, die vor dem Import redaktionell bestätigt werden müssen.
- `personen_biografien_import.csv`: direkt importierbare Datensätze als CSV.
- `personen_biografien_alle.csv`: alle 439 untersuchten Personen mit Status, Quelle und Handlungsempfehlung.
- `personen_biografien_import.xlsx`: übersichtliche Arbeitsmappe mit getrennten Prüflisten.

75 Personen konnten nicht sicher identifiziert werden; für sie wurde bewusst keine Biografie erfunden. Weitere 19 Datensätze sind Dubletten, Namensfragmente, falsche Entitätstypen oder fehlerhafte Zuordnungen und dürfen nicht automatisch importiert werden.

## Kompakter Prompt für Claude Code

```text
Arbeite im Projekt /Users/jakob/Claude Projekte. Lies zuerst die Projektanweisungen und analysiere das vorhandene Datenmodell sowie den bisherigen Supabase-Zugriff. Verwende als Eingabe ausschließlich:
/Users/jakob/Claude Projekte/outputs/personen_biografien_2026-08-06/personen_biografien_import.jsonl

Führe zunächst nur einen Dry Run aus:
1. Parse jede JSONL-Zeile und validiere UUID, full_name und biography_de.
2. Prüfe in der Tabelle persons, dass jede UUID genau einmal existiert, der gespeicherte Name plausibel passt und biography_de weiterhin NULL oder leer ist.
3. Überspringe Datensätze, die seit Erstellung der Datei verändert oder bereits befüllt wurden.
4. Zeige vor jeder Änderung eine Zusammenfassung: Anzahl importierbar, übersprungen, fehlerhaft sowie einige Beispieländerungen.
5. Verändere noch nichts und warte auf meine ausdrückliche Bestätigung.

Erst nach meiner Bestätigung:
- Aktualisiere ausschließlich persons.biography_de anhand der UUID; ändere keine Namen, Slugs, Quellenfelder oder Verknüpfungen.
- Nutze eine transaktionale beziehungsweise fehlertolerante Batch-Strategie und protokolliere Erfolg und Fehler pro UUID.
- Lies die aktualisierten Datensätze anschließend erneut aus und bestätige, dass exakt die freigegebenen Biografien gespeichert wurden.
- Gib zum Schluss eine kurze Importstatistik aus. Niemals die 156 Datensätze mit „Prüfung empfohlen“, die 75 Datensätze ohne sichere Biografie oder die 19 Bereinigungsfälle automatisch importieren.
```

## Manuelle Verwendung

Für einen manuellen Import zuerst `personen_biografien_import.xlsx` prüfen. Maßgeblich ist immer die UUID, nicht der Name. Die Tabelle `Prüfung empfohlen` enthält bereits formulierte Texte, aber mindestens einen offenen Identitäts-, Quellen- oder Qualitätsaspekt. Die Tabelle `Datenbereinigung` sollte separat bearbeitet werden, weil dort Zusammenführungen oder Modellkorrekturen statt Biografie-Updates erforderlich sind.
