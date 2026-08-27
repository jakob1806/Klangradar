-- Vierzehnte echte Event-Quelle der Stadt-Erweiterung, dritte für Frankfurt,
-- fünfte über Browserless-Rendering: die Frankfurter Museums-Gesellschaft
-- (museumskonzerte.de) lädt ihren Konzertkalender per JS nach. Config lokal
-- gegen per Browserless gerendertes HTML verifiziert (Deno, 26/26 Termine
-- korrekt geparst, 0 Fehler).
--
-- Datum ohne Uhrzeit auf der Übersichtsseite (nur Tag+Monatskürzel je
-- Kachel, z.B. "25" + "Okt") -- startDateTime landet dadurch auf 00:00 Uhr
-- Lokalzeit; die Detailseite pro Konzert hat die genaue Uhrzeit, aber der
-- Connector liest nur die Übersichtsliste (kein Nachladen von Detailseiten
-- vorgesehen). Kein Korrektheitsproblem für Auffindbarkeit/Sortierung nach
-- Datum, nur die angezeigte Uhrzeit ist ungenau -- Folgearbeit für eine
-- spätere Iteration, falls das stört.
--
-- Keine venue_id: alle Konzerte im Kaisersaal/Mozart-Saal der Alten Oper
-- Frankfurt, aber die Übersichtsliste nennt den Saal nicht separat pro
-- Kachel -- venueName bleibt null, kein Fuzzy-Match-Risiko.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Frankfurter Museums-Gesellschaft – Museumskonzerte (Rendered Scrape)',
  'scrape',
  'https://museumskonzerte.de/konzerte/',
  null,
  (select id from regions where type = 'city' and slug = 'frankfurt'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || 'Konzertseite nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "renderJs": true,
    "renderJsWaitMs": 6000,
    "itemSelector": "div.konzert_box_wrapper",
    "titleSelector": "h3.the_title",
    "urlSelector": "a.konzert_box",
    "dateSelector": ".day_nr",
    "timeSelector": ".month",
    "baseUrl": "https://www.museumskonzerte.de"
  }'::jsonb
);
