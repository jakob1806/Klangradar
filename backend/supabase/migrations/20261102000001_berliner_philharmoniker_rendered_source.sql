-- Zehnte echte Event-Quelle der Stadt-Erweiterung, fünfte für Berlin und
-- die ERSTE, die per Browserless (JS-Rendering statt rohem HTTP-GET)
-- eingebunden ist -- der Kalender lädt clientseitig per Vue nach, ein
-- normaler fetch() liefert nur eine leere <div class="concerts"></div>
-- (siehe docs/12-city-expansion-import.md, Abschnitt "Geprüft, aber
-- technisch nicht umsetzbar"). Config lokal gegen per Browserless
-- gerendertes HTML verifiziert (Deno, 6/6 echte Berliner Termine korrekt
-- geparst; Gastspiel-Tourdaten wie "Festivaltournee" nach Luzern/
-- Edinburgh/London über titleExcludeIfContains ausgefiltert, siehe
-- Quellenliste: "Gastveranstaltungen und mehrere Säle korrekt zuordnen").
--
-- config.renderJs=true weist ingest-source/core.ts an, den neuen
-- _shared/http/fetchRendered.ts-Pfad statt fetchWithRetry() zu nutzen --
-- braucht das Secret BROWSERLESS_API_TOKEN (siehe
-- deploy-edge-functions.yml), ohne das schlägt der Fetch mit einer
-- klaren Fehlermeldung fehl statt still leer zu bleiben.
--
-- Keine venue_id: Termine finden in mehreren Sälen der Philharmonie statt
-- (Großer Saal, Kammermusiksaal, Foyer Großer Saal, ...), venueName löst
-- per Fuzzy-Match auf.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Berliner Philharmoniker – Konzertkalender (Rendered Scrape)',
  'scrape',
  'https://www.berliner-philharmoniker.de/konzerte/kalender/',
  null,
  (select id from regions where type = 'city' and slug = 'berlin'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'Kalenderseite nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "renderJs": true,
    "renderJsWaitMs": 6000,
    "itemSelector": "div.concert-tile.image--hover",
    "titleSelector": ".concert-tile__title strong",
    "urlSelector": "a[href*=\"/konzerte/kalender/\"]",
    "dateSelector": ".concert-tile__info time",
    "venueSelector": ".concert-tile__info .align--right span",
    "titleExcludeIfContains": ["Festivaltournee"],
    "baseUrl": "https://www.berliner-philharmoniker.de"
  }'::jsonb
);
