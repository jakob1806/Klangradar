-- Elfte echte Event-Quelle der Stadt-Erweiterung, sechste für Berlin,
-- zweite über Browserless-Rendering: das Deutsche Symphonie-Orchester
-- Berlin lädt seinen Konzertkalender per JS nach. Config lokal gegen per
-- Browserless gerendertes HTML verifiziert (Deno, 68/68 Termine korrekt
-- geparst, 0 Fehler — bisher größte Einzelquelle dieser Stadt-Erweiterung).
--
-- Keine venue_id: Termine finden an vielen verschiedenen Orten statt
-- (Philharmonie Berlin, Haus des Rundfunks, Bode-Museum, Wilhelm Hallen,
-- ...), venueName löst per Fuzzy-Match auf.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Deutsches Symphonie-Orchester Berlin – Konzerte (Rendered Scrape)',
  'scrape',
  'https://www.dso-berlin.de/de/konzerte/',
  null,
  (select id from regions where type = 'city' and slug = 'berlin'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'Konzertseite nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "renderJs": true,
    "renderJsWaitMs": 7000,
    "itemSelector": "article.calendar-event",
    "titleSelector": ".calendar-event__heading",
    "urlSelector": "a.calendar-event__link",
    "dateSelector": "time.date-rows",
    "dateAttribute": "datetime",
    "venueSelector": ".date-rows__location",
    "baseUrl": "https://www.dso-berlin.de"
  }'::jsonb
);
