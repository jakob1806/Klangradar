-- Sechste echte Event-Quelle der Stadt-Erweiterung, zweite für Wien: die
-- Volksoper Wien liefert ihren Spielplan serverseitig gerendert mit
-- Schema.org-Microdata pro Termin inkl. einem separaten
-- <span itemprop="startDate" content="ISO..."> für Datum UND Uhrzeit in
-- einem Feld (kein Kombinieren von Datum+Zeit-Element nötig wie bei den
-- anderen Quellen). Config lokal gegen echtes HTML verifiziert (Deno,
-- 27 echte Termine korrekt geparst, 0 Fehler; "keine Vorstellung"-
-- Platzhaltertermine über titleExcludeIfContains ausgefiltert).
--
-- Keine venue_id: Termine finden an mehreren Orten im Haus statt
-- (Volksoper Hauptbühne, Balkon-Foyer, ...), venueName löst per
-- Fuzzy-Match auf.
insert into sources (
  name, type, url, venue_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Volksoper Wien – Spielplan (Scrape)',
  'scrape',
  'https://www.volksoper.at/spielplan/',
  null,
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || '"Disallow:" (leer, keine Einschränkung), kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": "article[itemtype=\"http://schema.org/Event\"]",
    "titleSelector": "h2.event-title",
    "urlSelector": "a[itemprop=\"url\"]",
    "dateSelector": "span[itemprop=\"startDate\"]",
    "dateAttribute": "content",
    "venueSelector": ".event-location",
    "titleExcludeIfContains": ["keine Vorstellung", "entfällt", "abgesagt"],
    "baseUrl": "https://www.volksoper.at"
  }'::jsonb
);
