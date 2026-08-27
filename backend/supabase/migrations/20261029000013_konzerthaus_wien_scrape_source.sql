-- Dritte echte Event-Quelle der Stadt-Erweiterung, erste für Wien: der
-- Kalender des Wiener Konzerthauses ist serverseitig gerendert
-- (.event-item), Config lokal gegen echtes HTML verifiziert (Deno, 4/4
-- echte Konzerte korrekt geparst, 6 Führungen/Backstage-Termine über
-- titleExcludeIfContains korrekt ausgefiltert, wie in der Quellenliste
-- ("Backstage und Führungen ausschließen") vorgegeben).
--
-- Zwei additive Fixes in parsers/scrape.ts waren dafür nötig, siehe
-- dortiger Kommentar/Diff im selben PR:
-- (1) Slash-getrenntes Datumsformat "TT/MM/JJ" (bisher nur Punkt-Format
--     "TT.MM.JJ" unterstützt),
-- (2) venueSelector strippt jetzt ein führendes Trennzeichen (hier: "∙")
--     aus dem Venue-Text, sonst scheitert der Fuzzy-Match gegen den
--     echten Venue-Namen ("∙ Schubert-Saal" statt "Schubert-Saal").
-- Beides rein additiv, bestehende Testsuite unter ingest-source/ bleibt
-- unverändert grün (5/5).
--
-- Keine venue_id: Konzerthaus Wien hat mehrere Säle (Mozart-Saal,
-- Schubert-Saal, Großer Saal, ...), venueName löst per Fuzzy-Match auf.
--
-- Deckung: Nur die initial serverseitig gerenderten ~10 Termine (kein
-- Pagination-Element gefunden, vermutlich "mehr laden"-Button per JS) —
-- täglicher Cron sammelt neu erscheinende Termine über Zeit auf.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Wiener Konzerthaus – Kalender (Scrape)',
  'scrape',
  'https://konzerthaus.at/kalender/',
  null,
  (select id from regions where type = 'city' and slug = 'vienna'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, '
    || '/kalender/ ist nicht disallowed, kein ClaudeBot-spezifischer Ausschluss.',
  'active',
  '{
    "itemSelector": ".event-item",
    "titleSelector": ".event-item__title",
    "urlSelector": ".event-item__link",
    "dateSelector": ".text-date",
    "timeSelector": ".event-item__details span:first-child",
    "venueSelector": ".event-item__details span:last-child",
    "titleExcludeIfContains": ["Backstage", "Führung"],
    "baseUrl": "https://konzerthaus.at"
  }'::jsonb
);
