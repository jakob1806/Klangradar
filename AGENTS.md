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
| Claude | 2026-09-30 | fix/internal-function-secret-vault-setup (abgeschlossen, PR #274) | Quellengesundheits-Audit: globaler Ingestion-/Hydration-Ausfall seit ca. 2026-08-28 gefunden und live behoben (fehlendes Vault-Secret `internal_function_secret`, betraf 40+ Cron-Funktionen). MPhil/Gärtnerplatz haben zusätzlich ein separates, echtes TCP-Timeout-Problem (Supabase-Egress zu diesen zwei Hosts) — noch offen, unabhängig vom Secret-Fix. |
| Claude | 2026-09-24 | fix/toolbar-edge-calendar-searchbar | Neues, eigenständiges Projekt "Wiesn Buddy" (`Wiesn Buddy/`) — natives iOS-Social-App für die Wiesn. Kein Bezug zu Klassik München/TKC; eigener Xcode-Projektordner, eigenes Supabase-Schema. |
| Claude | 2026-09-30 | kein Branch (eigener Ordner `Knabenchor Kalender-Sync/`) | Eigenständiger Scraper: Tölzer-Knabenchor-Konzerte -> iCloud-Kalender "Konzert & Oper". Kein Bezug zu Klassik München/TKC Kocyan Map/Wiesn Buddy. |
| Claude | 2026-10-04 | claude/hardening-* (Serie) | App-Review Punkte 1-11 (probe-source-Auth, Fehlerzustände iOS, iOS-CI, Tests, A11y) + Ticketlinks + Mehrstädte-Start; je Thema eigener PR |
| Claude | 2026-09-02 | redesign/veranstalter-portal  | Klangradar-KI: Datenanbindung/Performance-Fixes im klangradar-coach Edge-Function; Supabase-Migrationshygiene |

| Codex | 2026-09-24 | kein Branch (nur Analyse) | Wiesn Buddy: Strukturprüfung und externe Design-Mockups abgeschlossen; keine App-Dateien geändert. |

<!-- Neue Einträge oben anfügen, alte nach Abschluss entfernen. -->
