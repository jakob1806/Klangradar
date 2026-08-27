-- Zwölfte echte Event-Quelle der Stadt-Erweiterung, dritte für Wien,
-- dritte über Browserless-Rendering: die Wiener Philharmoniker laden
-- ihren Konzertkalender per JS nach. Config lokal gegen per Browserless
-- gerendertes HTML verifiziert (Deno, 242 Termine korrekt geparst,
-- 19 Fehler bei Items ohne extrahierbares Datum/Titel, übersprungen).
--
-- Bekannte Einschränkung (nicht behoben): Die Quellenliste empfiehlt
-- "Nur Wien-Termine übernehmen; mit Musikverein/Konzerthaus
-- deduplizieren" -- die Seite liefert aber eine vollständige Liste aus
-- vergangenen UND zukünftigen Terminen, Wien UND Tournee-Auftritten
-- (Grafenegg, Luzern, London, ...), ohne dass der bestehende
-- scrape-Connector nach einem data-isvienna/data-status-Attribut statt
-- extrahiertem Text filtern könnte. Kein Korrektheitsproblem (idempotente
-- Upserts, die App-Abfragen zeigen ohnehin nur zukünftige Events), aber
-- unnötiger Ingestion-Overhead und potenzielle Dubletten mit Musikverein/
-- Konzerthaus Wien bei echten Wien-Konzerten -- Folgearbeit für eine
-- spätere Iteration.
--
-- Keine venue_id: Termine an vielen verschiedenen Orten (Musikverein,
-- Tournee-Spielstätten, ...), venueName löst per Fuzzy-Match auf.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Wiener Philharmoniker – Konzerte (Rendered Scrape)',
  'scrape',
  'https://www.wienerphilharmoniker.at/de/konzerte',
  null,
  (select id from regions where type = 'city' and slug = 'vienna'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'Konzertseite nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "renderJs": true,
    "renderJsWaitMs": 7000,
    "itemSelector": ".event-module",
    "titleSelector": "h2 a",
    "urlSelector": "h2 a",
    "dateSelector": ".short-date",
    "timeSelector": ".cell.h",
    "venueSelector": ".event-area",
    "baseUrl": "https://www.wienerphilharmoniker.at"
  }'::jsonb
);
