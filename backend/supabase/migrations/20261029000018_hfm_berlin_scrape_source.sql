-- Achte echte Event-Quelle der Stadt-Erweiterung, dritte für Berlin:
-- Hochschule für Musik Hanns Eisler Berlin (Priorität C laut
-- Nutzer-Quellenliste, "viele kostenlose Nachwuchskonzerte") listet ihren
-- Veranstaltungskalender serverseitig gerendert. Config lokal gegen
-- echtes HTML verifiziert (Deno, 10/10 Termine korrekt geparst).
--
-- Beim Bau dieser Quelle wurde ein echter, vorbestehender Bug in
-- parseFlexibleDate() gefunden und behoben (siehe scrape.ts-Diff im
-- selben PR): die Alternation "(\d{2}|\d{4})" für das Jahr im Format
-- "TT.MM.JJJJ"/"TT.MM.JJ" nahm bei einem 4-stelligen Jahr wie "2026"
-- fälschlich nur die ersten zwei Ziffern ("20" -> Jahr 2020 statt 2026),
-- weil Regex-Alternation von links nach rechts prüft und beim ersten
-- Treffer stoppt, statt die längere Alternative zu bevorzugen. hfm-
-- berlin.de ist die erste bisherige Quelle mit einem echten 4-stelligen
-- Jahr in diesem Format ("10.09.2026") -- alle bisherigen Quellen nutzten
-- zweistellige Jahre, daher blieb der Bug unbemerkt. Fix: Alternation auf
-- "(\d{4}|\d{2})" umgestellt (4-stellig zuerst versuchen), betrifft auch
-- das slash-getrennte Format von 20261029000013. Durch die bestehende
-- Testsuite (5/5 weiterhin grün) und Neu-Verifikation aller bisherigen
-- HTML-Fixtures (Wien, Hamburg, Kronberg -- alle unverändert korrekt)
-- als rein additiv/nicht-regressiv abgesichert.
--
-- Zusätzlich: "H" als weiteres Uhrzeit-Suffix neben "Uhr" ergänzt
-- ("19.30 H" statt "19.30 Uhr").
--
-- Keine venue_id: kein separates Venue-Element im HTML dieser Quelle
-- gefunden (Ortsangabe steht unstrukturiert im selben Textblock wie der
-- Preis, ohne eigene CSS-Klasse) -- venueName bleibt null, die Events
-- landen dennoch korrekt zugeordnet zur Hochschule selbst als Fallback.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Hochschule für Musik Hanns Eisler Berlin – Veranstaltungen (Scrape)',
  'scrape',
  'https://www.hfm-berlin.de/veranstaltungen/',
  null,
  (select id from regions where type = 'city' and slug = 'berlin'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'Kalenderseite nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": ".c-events-list__item",
    "titleSelector": "h3",
    "urlSelector": "a[aria-label^=\"zur Veranstaltung\"]",
    "dateSelector": ".c-events-list__date",
    "baseUrl": "https://www.hfm-berlin.de"
  }'::jsonb
);
