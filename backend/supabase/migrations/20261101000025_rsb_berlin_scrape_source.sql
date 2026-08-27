-- Neunte echte Event-Quelle der Stadt-Erweiterung, vierte für Berlin:
-- Rundfunk-Sinfonieorchester Berlin (Priorität B laut Nutzer-
-- Quellenliste) listet seine nächsten Konzerte serverseitig gerendert.
-- Config lokal gegen echtes HTML verifiziert (Deno, 5/5 Termine korrekt
-- geparst).
--
-- Kleinere Quelle als die bisherigen (nur 5 Termine auf der Seite,
-- "Nächste Konzerte"-Widget statt vollständigem Kalender) -- trotzdem
-- übernommen, da echt, kostenlos zu pflegen (kein zusätzlicher Parser-
-- Aufwand) und eine weitere Berliner Ensemble-Quelle neben den Opern-
-- Venues.
--
-- Keine venue_id: Ortsangabe steht im selben Textblock wie die Uhrzeit
-- ohne eigene CSS-Klasse ("10:00 Haus des Rundfunks" ein Textknoten),
-- daher keine saubere venueSelector-Extraktion möglich -- venueName
-- bleibt null.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Rundfunk-Sinfonieorchester Berlin – Konzerte (Scrape)',
  'scrape',
  'https://www.rsb-online.de/konzerte/',
  null,
  (select id from regions where type = 'city' and slug = 'berlin'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'Konzertseite nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": ".ConcertListItem",
    "titleSelector": ".ConcertListItem-Title",
    "urlSelector": ".ConcertListItem-Content",
    "dateSelector": ".ConcertListItem-Time",
    "timeSelector": ".ConcertListItem-Place",
    "baseUrl": "https://www.rsb-online.de"
  }'::jsonb
);
