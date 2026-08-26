-- Siebte echte Event-Quelle der Stadt-Erweiterung, zweite für Frankfurt:
-- Kronberg Academy (Priorität C laut Nutzer-Quellenliste, "Kandidaten
-- geografisch der Konzertregion Frankfurt zuordnen" -- Kronberg im Taunus
-- liegt direkt bei Frankfurt) listet ihren Kalender serverseitig gerendert
-- mit sauberem <time datetime="ISO..."> pro Termin. Config lokal gegen
-- echtes HTML verifiziert (Deno, 10/10 Termine korrekt geparst).
--
-- Keine venue_id: Termine finden im Casals Forum (mehrere Säle) UND
-- auswärts statt (siehe erstes Testevent: Rhein-Main-Philharmoniker
-- Frankfurt am Main als Gast), venueName löst per Fuzzy-Match auf.
insert into sources (
  name, type, url, venue_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Kronberg Academy – Veranstaltungen (Scrape)',
  'scrape',
  'https://www.kronbergacademy.de/veranstaltungen',
  null,
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'Kalenderseite nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": ".events__list",
    "titleSelector": ".events__title a",
    "urlSelector": ".events__title a",
    "dateSelector": "time",
    "dateAttribute": "datetime",
    "venueSelector": ".events__location",
    "titleExcludeIfContains": ["Führung"],
    "baseUrl": "https://www.kronbergacademy.de"
  }'::jsonb
);
