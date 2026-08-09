# Import der Ensemble-Biografien

Stand: 6. August 2026. Die produktive Datenbank wurde durch die Erstellung dieses Pakets nicht verändert.

## Empfohlener automatischer Import

Verwende `ensemble_biografien_import.jsonl`. Die Datei enthält ausschließlich die 30 als **Importbereit** eingestuften Datensätze. Jeder Eintrag besitzt die vorhandene UUID und den neuen Wert für `description_de`.

Geeigneter Auftrag an Claude Code:

> Lies `outputs/ensemble_biografien_2026-08-06/ensemble_biografien_import.jsonl`. Prüfe zuerst in einem Dry Run, dass jede UUID genau einmal in `ensembles` existiert und `description_de` weiterhin leer ist. Zeige mir die geplanten Änderungen. Importiere erst nach meiner ausdrücklichen Bestätigung ausschließlich `description_de`; identifiziere jeden Datensatz über `id`, nicht über den Namen. Überspringe Datensätze, die sich seit dem Export verändert haben, und gib anschließend eine Erfolgs-/Fehlerliste aus.

`ensemble_biografien_mit_pruefung.jsonl` enthält zusätzlich vier fertige Entwürfe, deren Ensemblebezeichnung oder Identität vorher kurz redaktionell bestätigt werden muss.

## Manueller Import

Öffne `ensemble_biografien_import.xlsx` und arbeite im Blatt **Importbereit**. Kopiere die Spalte **Biografie (description_de)** anhand der UUID in das gleichnamige Datenbankfeld. Alternativ enthält `ensemble_biografien_import.csv` dieselben 30 Datensätze als Semikolon-CSV.

## Nicht ungeprüft importieren

Das Blatt **Datenbereinigung** enthält elf Dubletten, abgeschnittene Namen, Institutionen oder projektbezogene Mitwirkende. Für diese Einträge wurde bewusst keine Biografie erfunden. Die jeweils empfohlene Bereinigung steht in der letzten Spalte.
