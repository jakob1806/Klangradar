-- Dreizehnte echte Event-Quelle der Stadt-Erweiterung, vierte für Hamburg,
-- vierte über Browserless-Rendering: die Symphoniker Hamburg (Residenz-
-- orchester der Laeiszhalle) laden ihren Konzertkalender per JS (TYPO3/
-- Masonry-Grid) nach. Config lokal gegen per Browserless gerendertes HTML
-- verifiziert (Deno, 56/56 Termine korrekt geparst, 0 Fehler).
--
-- Die Liste enthält neben Hamburger Konzerten auch Gastspiel-Termine an
-- anderen Orten (z.B. Großröhrsdorf) -- das ist beabsichtigt (echte Termine
-- des Orchesters) und wird wie bei den anderen Quellen über den bestehenden
-- Venue-Fuzzy-Match aufgelöst, kein Ausschlusskriterium nötig.
--
-- Keine venue_id: Termine finden an verschiedenen Sälen der Laeiszhalle
-- sowie auswärtigen Gastspielorten statt, venueName löst per Fuzzy-Match auf.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Symphoniker Hamburg – Konzerte (Rendered Scrape)',
  'scrape',
  'https://www.symphonikerhamburg.de/konzerte',
  null,
  (select id from regions where type = 'city' and slug = 'hamburg'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — kein robots.txt vorhanden '
    || '(liefert 404-Seite statt Regeln), kein ClaudeBot-spezifischer Ausschluss ermittelbar.',
  'active',
  '{
    "renderJs": true,
    "renderJsWaitMs": 6000,
    "itemSelector": "div.magazine-item",
    "titleSelector": "h2",
    "urlSelector": "a.cta.ctaWhite",
    "dateSelector": ".kDate",
    "venueSelector": ".kOrt",
    "baseUrl": "https://www.symphonikerhamburg.de"
  }'::jsonb
);
