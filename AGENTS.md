# Agenten-Koordination

Mehrere KI-Coding-Agenten (u.a. Claude, Codex) arbeiten parallel und
unkoordiniert an diesem Repo. Das hat bereits zu Kollisionen geführt:
doppelt gebaute Features (Coach vs. Personal Concierge), ein komplett
überschriebenes Veranstalter-Portal-Layout und still verschluckte
Änderungen bei Auto-Merges. Diese Datei soll das verhindern.

## Regeln

1. **Vor Arbeitsbeginn eintragen.** Jeder Agent trägt zu Beginn einer
   Session unten einen Eintrag ein: Name, Datum, Branch, Kurzbeschreibung.
2. **Vor Arbeitsbeginn lesen.** Prüfe, ob ein anderer Agent gerade an
   überlappenden Dateien/Features arbeitet, bevor du etwas Neues baust,
   das dieselbe Funktionalität abdecken könnte.
3. **Nach Abschluss aktualisieren.** Eintrag auf "abgeschlossen" setzen
   oder entfernen, wenn die Arbeit gemerged/live ist.
4. **Commit-Attribution.** Jeder Commit bekommt einen `Co-Authored-By`-
   Trailer mit dem Namen des jeweiligen Agenten/Modells, damit sich
   `git log` jederzeit nach Urheber filtern lässt.
5. **Branch-Konvention.** Feature-Branches nach Agent präfixen, wo möglich
   (`claude/*`, `codex/*`), damit auf GitHub sofort erkennbar ist, wer was
   begonnen hat.

## Aktueller Stand

| Agent  | Datum      | Branch                        | Woran                                                                 |
|--------|------------|--------------------------------|------------------------------------------------------------------------|
| Claude | 2026-09-02 | redesign/veranstalter-portal  | Klangradar-KI: Datenanbindung/Performance-Fixes im klangradar-coach Edge-Function; Supabase-Migrationshygiene |

<!-- Neue Einträge oben anfügen, alte nach Abschluss entfernen. -->
