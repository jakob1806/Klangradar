-- Fünfte echte Event-Quelle der Stadt-Erweiterung, zweite für Berlin: die
-- Komische Oper Berlin liefert ihren Spielplan serverseitig gerendert MIT
-- Schema.org-Microdata pro Termin (itemscope itemtype="Event", ISO-Datum
-- direkt in <meta itemprop="startDate" content="...">), aber keine
-- eigenständige JSON-LD-Quelle -- der bestehende schema_org-Connector
-- greift daher nicht, dafür der scrape-Connector mit dateAttribute auf das
-- meta-Tag. Config lokal gegen echtes HTML verifiziert (Deno, 35 echte
-- Termine korrekt geparst, Führungen über titleExcludeIfContains
-- ausgefiltert).
--
-- Bisher größte Einzelquelle dieser Stadt-Erweiterung (35 vs. 4-25 bei den
-- anderen drei), da die komplette Spielplan-Kalenderseite (nicht nur ein
-- Ausschnitt) serverseitig vorliegt.
--
-- Keine venue_id: Termine finden an mehreren Orten statt (Schillertheater
-- als aktuelles Ausweichquartier während der Sanierung, Infocenter,
-- Flughafen Tempelhof für Sonderformate, ...), venueName löst per
-- Fuzzy-Match auf.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Komische Oper Berlin – Spielplan (Scrape)',
  'scrape',
  'https://www.komische-oper-berlin.de/spielplan/',
  null,
  (select id from regions where type = 'city' and slug = 'berlin'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'praktisch leer (keine Disallow-Regeln), kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": ".performance",
    "titleSelector": ".performance__link span[itemprop=\"name\"]",
    "urlSelector": ".performance__link",
    "dateSelector": "meta[itemprop=\"startDate\"]",
    "dateAttribute": "content",
    "venueSelector": ".performance__location",
    "titleExcludeIfContains": ["Führung"],
    "baseUrl": "https://www.komische-oper-berlin.de"
  }'::jsonb
);
