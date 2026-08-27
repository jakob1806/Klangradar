-- Zweite echte Event-Quelle der Stadt-Erweiterung (Frankfurt): Alte Oper
-- Frankfurts Programmseite hat kein Schema.org-Markup, aber eine sauber
-- strukturierte, serverseitig gerenderte Event-Liste (.event-item) —
-- gescrapt mit dem bestehenden generischen scrape-Connector, Config lokal
-- gegen echtes HTML verifiziert (Deno, 10/10 Events korrekt geparst:
-- Titel/Datum/Uhrzeit/Saal/Bild/Link).
--
-- Zwei Lücken im bisherigen Datumsparser (parsers/scrape.ts) mussten dafür
-- geschlossen werden, siehe dortiger Kommentar/Diff im selben PR:
-- (1) "14 September 2026" ohne Punkt nach der Tageszahl (bisher zwingend
--     "14. September 2026"),
-- (2) "20:00" ohne "Uhr"-Suffix (bisher zwingend "20:00 Uhr").
-- Beides rein additiv (macht bestehende Formate weiterhin erkennbar,
-- Testsuite unter ingest-source/ läuft unverändert grün), kein bestehender
-- Scraper wird dadurch beeinflusst.
--
-- Keine venue_id: Alte Oper hat zwei Säle (Großer Saal, Mozart Saal),
-- venueName löst per Fuzzy-Match auf.
--
-- Deckung: ~10 sichtbare Events beim ersten Laden (kein Pagination-Element
-- gefunden, vermutlich Infinite-Scroll/AJAX nachgeladen) — täglicher Cron
-- sammelt neu erscheinende Termine über Zeit auf, ähnlich wie Münchens
-- Quellen. Genre-Filterung (Alte Oper zeigt auch Lesungen/Kabarett neben
-- Konzerten) bewusst NICHT vorgenommen — Umfang für einen ersten Wurf.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Alte Oper Frankfurt – Programm (Scrape)',
  'scrape',
  'https://www.alteoper.de/de/programm',
  null,
  (select id from regions where type = 'city' and slug = 'frankfurt'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || '/de/programm ist nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": ".event-item",
    "titleSelector": ".event-item__headline .link__text",
    "urlSelector": ".event-item__headline",
    "dateSelector": ".event-time",
    "venueSelector": ".event-time > span:last-child",
    "imageSelector": ".event-item__picture img",
    "imageAttribute": "src",
    "baseUrl": "https://www.alteoper.de"
  }'::jsonb
);
