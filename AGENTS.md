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
| Claude | 2026-10-26 | claude/abos-saisonplaner, claude/perf-home | Abos/Zyklen, Saisonplaner, Konzerttagebuch, Besetzungsänderungen, Live-Aktivität, Performance (ios-native + backend) |
| Claude | 2026-10-18 | claude/email-preferences | E-Mail-Einstellungen (iOS + Flutter): Newsletter-Einwilligung mit Zeitstempel, E-Mail-Schalter pro Anlass, Abmelde-Token. Versand selbst noch nicht gebaut (Mail-Provider offen). |
| Claude | 2026-10-15 | claude/onboarding-follow-speed | Onboarding-Folgen-Schritt (iOS + Flutter): gerankte Top-Vorschläge + Serversuche per RPC onboarding_follow_suggestions statt kompletter Tabellen (persons >3.000). |
| Claude | 2026-10-12 | claude/fix-ingestion-starvation | Quellen-Audit #2: run-all-sources hängt seit 2026-09-30 in Endlosschleife an 5 Quellen (Abbruch → nie last_run_at → sofort wieder fällig), alle anderen Quellen verhungern. Fix in run-all-sources + Quellen-Configs reparieren. |
| Claude | 2026-10-15 | claude/oauth-onboarding-first (abgeschlossen, PR #336) | Apple-/Google-/E-Mail-Login überspringt das Onboarding nicht mehr (iOS + Flutter): neue Accounts landen bei "Persönliche Daten", nur Rückkehrer gehen direkt in die App. |
| Claude | 2026-09-30 | fix/internal-function-secret-vault-setup (abgeschlossen, PR #274) | Quellengesundheits-Audit: globaler Ingestion-/Hydration-Ausfall seit ca. 2026-08-28 gefunden und live behoben (fehlendes Vault-Secret `internal_function_secret`, betraf 40+ Cron-Funktionen). MPhil/Gärtnerplatz haben zusätzlich ein separates, echtes TCP-Timeout-Problem (Supabase-Egress zu diesen zwei Hosts) — noch offen, unabhängig vom Secret-Fix. |
| Claude | 2026-09-24 | fix/toolbar-edge-calendar-searchbar | Neues, eigenständiges Projekt "Wiesn Buddy" (`Wiesn Buddy/`) — natives iOS-Social-App für die Wiesn. Kein Bezug zu Klassik München/TKC; eigener Xcode-Projektordner, eigenes Supabase-Schema. |
| Claude | 2026-09-30 | kein Branch (eigener Ordner `Knabenchor Kalender-Sync/`) | Eigenständiger Scraper: Tölzer-Knabenchor-Konzerte -> iCloud-Kalender "Konzert & Oper". Kein Bezug zu Klassik München/TKC Kocyan Map/Wiesn Buddy. |
| Claude | 2026-10-04 | claude/hardening-* (Serie) | App-Review Punkte 1-11 (probe-source-Auth, Fehlerzustände iOS, iOS-CI, Tests, A11y) + Ticketlinks + Mehrstädte-Start; je Thema eigener PR |
| Claude | 2026-10-27 | claude/journal-editor-fixes | Konzert-Journal: Editor-Fixes, Vorschläge, Eintrag im Profil; Journal zählt als Besuch (Migration 000122); Konzertseite: Lücken, „Ticket & Platz“-Kachel; „Neu in Klangradar“ (WhatsNew.json → App-Popup + TestFlight-Hinweis) |
| Claude | 2026-10-27 | claude/onboarding-landing-redesign | Onboarding-Startseite neu, „Wer spielt?“ ersetzt Mitwirkende bei ≤4 (inkl. Ensembles), Biografie-Worker mit Wikipedia-Rückfall (Migration 000123), iPad-Titelbild |
| Claude | 2026-10-27 | claude/testflight-auto-watch | TestFlight-Wächter: lokaler launchd-Job lädt nach Merge + grünen/freigegebenen Deploys automatisch hoch (ios-native/Scripts/testflight-watch.sh) |
| Claude | 2026-10-27 | claude/konzert-abos-ausbau | Konzert-Abos: BRSO über Konzertkalender, mphil-Mehrfach-Abos, Abo-Katalog „Abos entdecken“, Fix „Ich habe dieses Abo“ (Migration 000127), Abo-Seite Navigation/Bilder |
| Claude | 2026-10-27 | claude/subscriptions-munich | Abo-Erkennung: BRSO-Parser repariert, neu Rundfunkorchester, BR-Chor, MKO, Gärtnerplatztheater (Migration 000125) |
| Claude | 2026-10-28 | claude/freunde-ausbau | Freunde: Navigation zu Profilen/Plänen repariert, Freundesprofil neu; Social-Ausbau (Migration 000128): Ich komme mit, Applaus/Antworten im Nachklang, Konzert-Buddys, Euer Jahr, Gruppen |
| Claude | 2026-10-28 | claude/plus-experience | Plus-Erlebnis: neue Paywall mit Testphasen-Ablauf, Willkommen/Übersicht, Plus-Hinweise in Profil/KI/Mitteilungen/Onboarding, alternative App-Icons |
| Claude | 2026-10-28 | claude/onboarding-nach-anmeldung | Onboarding (Folgen usw.) auch nach Apple-/Google-Anmeldung aus dem Profil, wenn fürs Konto noch offen |
| Claude | 2026-10-27 | claude/premium-konzertjahr | Klangradar Plus serverseitig (Codes, Migration 000126), Sofort-Alarm für Plus im push-dispatcher, Konzertjahr-Redesign, schlichteres „Neu in Klangradar“ |
| Claude | 2026-10-27 | claude/fix-home-timeouts | Störung Startseite: Beliebtheits-Cache für onboarding_follow_suggestions (Migration 000124), Retry/Cache-Fallback/deutsche Fehler im Home-Feed |
| Claude | 2026-10-28 | claude/freunde-prozess-ausbau | Freunde-Ausbau (12 Punkte): Migration 000129, notify-social, iOS Features/Friends |
| Claude | 2026-09-02 | redesign/veranstalter-portal  | Klangradar-KI: Datenanbindung/Performance-Fixes im klangradar-coach Edge-Function; Supabase-Migrationshygiene |

| Codex | 2026-09-24 | kein Branch (nur Analyse) | Wiesn Buddy: Strukturprüfung und externe Design-Mockups abgeschlossen; keine App-Dateien geändert. |

<!-- Neue Einträge oben anfügen, alte nach Abschluss entfernen. -->
| Claude | 2026-10-29 | claude/abos-profil-werkeinfuehrung | Abo-Bereich im Profil + Ensembleseite, Abo-Bildausschnitt, Fertig-Button Stadtwechsler, Werkeinführungen über Wikidata, Admin-Seite /werkeinfuehrungen |
| Claude | 2026-10-29 | claude/dashboard-erweiterungen | Admin: /abos, /datenluecken, /bekanntheit, /moderation, /plus, Einreichungen unter /werkeinfuehrungen; Veranstalter: Abos, Tickets & Preise, Werkeinführungen, Besetzungsänderung, Analytics-Trichter/CSV, Publikum |
| Claude | 2026-10-29 | claude/admin-startseite | Admin-Startseite klangradar.com/admin, Login-Standardziel /admin, NAV_GROUPS in nav-groups.ts |
| Claude | 2026-10-29 | claude/promote-ausbau | Push & Promote: Staffelpreise nach Vorlaufzeit (/promotion-preise), Laufzeit, Tages-/Gesamtbudget, Targeting in active_event_promotions |
| Claude | 2026-10-28 | claude/onboarding-top-vorschlaege | Onboarding: Folgen-Vorschläge nach Bekanntheits-Score (Wikipedia-Aufrufe), Genre-Kacheln, kleinere Suchtreffer-Kacheln |
| Claude | 2026-10-29 | claude/abos-profil-geschmack | Abo-Titelbild = Ensemble, Abos im Profil dezenter, Dein Geschmack neu, Interessen wie Onboarding, BR-Quellen Rundfunkorchester/BR-Chor + Reihen, TestFlight-Mail nur an Jakob |
| Claude | 2026-10-29 | claude/sammlungen-duplikate | Sammlungen per Regel (Person/Ensemble/Spielstätte), Duplikatprüfung Personen/Ensembles präziser + neue Prüfansicht, Werke-Lauf im Hintergrund, TestFlight-Hinweis mit Homebrew-Ruby |
| Claude | 2026-10-29 | claude/admin-ux-duplikate | Werk-Duplikate mit Gegenbeweis-Filter, Duplikate beim Anlegen erkennen, Tastatursteuerung Duplikate, Listen-Baukasten Personen/Ensembles/Venues, Zuletzt geöffnet/erledigt auf /admin |
| Claude | 2026-10-30 | claude/supabase-entlastung | Supabase-Last: Cron-Takte gesenkt/versetzt, cron.job_run_details begrenzt, ingestion_runs-Index |
| Claude | 2026-10-30 | claude/modest-mayer-dn1xt9 | Konzertseite: Ticket anbieten/Privat ins „…“-Menü, Pause als eigener Programmpunkt; Meine Abos im Profil neu; Dein Geschmack neu (verlinkte Einträge); Sammlungs-Regelsuche repariert (Migration 000138); Plus-Diamant im Profil, Suche ohne „nicht gefunden“-Flackern, Karten-Buttons, Staatsoper-Partien + Neusync, Admin: Bereiche mit Reitern, /eingang, ⌘K, Veranstalterportal 4 Punkte, Eventgruppen mit Wahrscheinlichkeit |
| Claude | 2026-10-31 | claude/event-detail-pause | Ticket übrig/Privat hingehen aus Konzertseite in Freunde verlegt, Pause als eigene Programmzeile (iOS + Flutter) |
