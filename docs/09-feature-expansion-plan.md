# Erweiterungsplan (Stand 2026-08-04)

Grundlage: 15 Feature-Wünsche aus dem Nutzer-Chat vom 2026-08-04, abgeglichen mit dem
tatsächlichen Code-/Migrationsstand (siehe Bestandsaufnahme unten je Punkt). Ziel dieses
Dokuments: nichts aus der Liste verlieren, auch wenn nicht alles auf einmal gebaut wird.
Ergänzt `07-roadmap.md`/`06-mvp-plan.md` um die konkreten 15 Punkte statt sie zu ersetzen.

**Status-Legende:** ⬜ nicht vorhanden · 🟨 teilweise vorhanden · 🟩 vollständig

## Bearbeitungsreihenfolge (vorgeschlagen)

Kriterium: Nutzwert pro Aufwand, und was auf bereits vorhandener Infrastruktur aufbaut statt
neue Grundlagen zu brauchen. Jede Phase ist ein eigener Arbeitsblock, den man einzeln
abschließen und ausliefern kann.

### Phase A — Bestehendes zu Ende bauen (kein Neuland)
Diese Punkte haben schon Backend-Tabellen/-Functions oder UI-Grundgerüst — hier fehlt vor
allem das letzte Stück, nicht die Architektur.

1. **Punkt 2 — Benachrichtigungen serverseitig aktivieren** 🟨
   `push_tokens`/`notification_settings_screen.dart` existieren, es fehlt der serverseitige
   Trigger (Event geändert/Ticketstart/fast ausverkauft → tatsächlich Push versenden). Ohne
   das ist die Einstellungsseite reine Attrappe.
2. **Punkt 10 — Änderungstransparenz sichtbar machen** 🟨
   `events_last_seen_at`, `cancellation_candidates` erfassen Änderungen bereits serverseitig.
   Fehlt: ein "Was hat sich geändert"-Hinweis auf der Event-Detail-Seite und die Verknüpfung
   zu Punkt 2 (Favoriten-Nutzer benachrichtigen).
3. **Punkt 9 — Ticket-/Preisfunktionen abrunden** 🟨
   `ticket_providers`, `event_ticket_links`, `enrich-event-prices` (heute deployed, siehe
   Bugfix-Teil) sind da. Fehlt: "Kostenlos"-Hervorhebung auf Home/Suche über den bestehenden
   `is_free`-Flag hinaus, Ermäßigungs-Badge, toter-Link-Meldung (Überschneidung mit Punkt 13).
4. **Punkt 1 — Kalender zu echter Sammlung ausbauen** 🟨
   Favoriten + ICS/Kalender-Sync existieren. Fehlt: Status "interessiert" vs. "besuche ich"
   (heute nur ein binäres Herz), Sammlungsansicht nach Künstler/Werk/Ort statt nur Liste.

### Phase B — Datenqualität sichtbar machen (Vertrauen der Nutzer)
5. **Punkt 14 — Quellen-/Vertrauensanzeige für Endnutzer** 🟨
   `field_provenance` existiert und wird bereits für Werk-Felder im Event-Detail angezeigt
   (`SourceHint`/`FieldSource`). Ausbauen auf Venue-/Personen-Kernfelder + sichtbares Label
   "automatisch erkannt" vs. "redaktionell geprüft" statt nur "Zuletzt geprüft"-Datum.
6. **Punkt 13 — Nutzer-Meldefunktion** ⬜
   Neu: Meldebutton auf Event-/Venue-/Personen-Detail ("Bild falsch", "Zeit falsch", "Werk
   fehlt" etc.), landet in einer Review-Queue (nicht in `error_reports` — das ist reines
   App-Crash-Logging und sollte nicht zweckentfremdet werden). Braucht eine neue Tabelle
   `content_reports` + Admin-Review-UI.

### Phase C — Substanzielle neue Bereiche
7. **Punkt 6 — Programm-Explorer** 🟨→🟩
   `works` hat schon fast alle Felder (Komponist, Opus, Tonart, Jahr, Dauer, Sätze,
   Besetzung, Epoche fehlt als eigenes Feld). Fehlt komplett: eigener Werk-Detail-Screen +
   "alle Aufführungen dieses Werks"-Liste. Baut auf dem heute reparierten
   Komponisten-Backfill (`enrich-work-composer`) auf — je vollständiger die Werkdaten, desto
   sinnvoller dieser Explorer.
8. **Punkt 4 — Suche natürlichsprachlich erweitern** 🟨
   `search_all` (trgm) deckt Tippfehler ab. Fehlt: Synonyme/alternative Namen, kombinierbare
   Filter aus Freitext ("Mahler unter 50 Euro"), gespeicherte Suchen (nur Verlauf vorhanden).
9. **Punkt 3 — "Für dich"-Bereich** 🟨→🟩
   `recommended_events`-RPC existiert (siehe `docs/08-home-feed-recommendation-algorithm.md`,
   laut Memory: Phase A ist Startpunkt, noch nicht implementiert). Dieser Punkt IST bereits
   geplant — hier nur verweisen, nicht doppelt planen.
10. **Punkt 5 — Karten-/Umkreissuche erweitern** 🟨
    Karte + Umkreisfilter (`ST_DWithin`) vorhanden. Fehlt: Reisezeit/ÖPNV-Live-Daten, Route
    entlang mehrerer Konzerte, Parkplatz-Feld bei Venues.

### Phase D — Neue, eigenständige Features (größerer Aufwand)
11. **Punkt 12 — Konzertplanung für einen Abend** ⬜ — kombiniert Kalender+Karte+Gastro-Daten,
    baut auf Phase A/C auf, macht vorher wenig Sinn.
12. **Punkt 11 — Redaktionelle Inhalte** ⬜ — braucht ein Redaktions-UI im Admin-Dashboard und
    eine "kuratiert"-Kennzeichnung, die sich gut mit Punkt 14 (Quellenanzeige) kombinieren
    lässt.
13. **Punkt 7/8 — Profile verfeinern** 🟨 — "ähnliche Künstler", frühere-Auftritte-Historie,
    Sitzplan/Akustik bei Venues: additive Erweiterungen auf bestehenden Screens, kein neuer
    Unterbau nötig, daher niedrige Priorität aber jederzeit einschiebbar.
14. **Punkt 15 — Mehrsprachigkeit & Barrierefreiheit** ⬜/🟨 — Englisch fehlt komplett (keine
    Intl-Infrastruktur), Barrierefreiheit ist bisher nur bei Venues abgebildet (App-weite
    Screenreader-/Kontrast-Arbeit lief laut Memory teilweise bereits, siehe
    `project_accessibility_audit_state`). Bewusst spät, weil Lokalisierung nachträglich
    aufwändiger wird, je mehr Screens dazukommen — aber nicht aufschieben bis "fertig genug",
    sondern rechtzeitig vor einem öffentlichen Launch einplanen (siehe `06-mvp-plan.md`).

## Bewusst zurückgestellt / an anderer Stelle bereits geplant
- Punkt 3 ("Für dich") ist in `08-home-feed-recommendation-algorithm.md` bereits im Detail
  geplant — hier keine Parallel-Planung, nur Referenz.
- ML-/Embedding-Empfehlungen, Apple Wallet, Live Activities, Widgets: bereits in
  `07-roadmap.md` Phase 5/6 verortet, hier nicht dupliziert.

## Arbeitsweise
Jede Phase wird als eigener Durchgang bearbeitet (eigene Tasks/PRs), nicht alles auf einmal.
Nach jeder Phase: kurzer Check gegen diese Liste, damit sichtbar bleibt, was noch offen ist —
dieses Dokument ist der Fortschritts-Tracker für die 15-Punkte-Liste, nicht nur eine
einmalige Notiz.
