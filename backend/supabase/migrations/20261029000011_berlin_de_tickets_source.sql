-- Erste echte Event-Quelle für die Stadt-Erweiterung (Berlin): die offizielle
-- Berlin.de-Ticketseite liefert für ihre Konzertübersicht echtes
-- Schema.org-MusicEvent-JSON-LD (verifiziert per curl, 15 Events zum
-- Zeitpunkt dieser Migration, jedes mit Titel/Datum/Venue/Preis/Ort) — nutzt
-- den bereits bestehenden generischen schema_org-Connector
-- (parsers/schema_org.ts), keine venue_id nötig: Events aus vielen
-- verschiedenen Berliner Venues werden per Fuzzy-Match gegen venueName
-- aufgelöst (siehe matching.ts resolveVenue()), genau wie bei BayernCloud.
--
-- Deckung: Diese eine Seite listet nur eine Momentaufnahme kuratierter
-- Highlight-Events, keine vollständige Berliner Konzertlandschaft (anders
-- als Münchens ~900 Events, die aus 10 einzeln über Wochen gebauten
-- Venue-spezifischen Quellen stammen, siehe docs/12-city-expansion-import.md).
-- Rechtlich UNGEPRÜFT wie die übrigen Scrape-/Schema.org-Quellen dieser
-- Stadt-Erweiterung — siehe docs/10-legal-status.md.
insert into sources (
  name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config
) values (
  'Berlin.de – Klassische Konzerte (Schema.org)',
  'schema_org',
  'https://www.berlin.de/tickets/klassische-konzerte/',
  null,
  (select id from regions where type = 'city' and slug = 'berlin'),
  1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — Schema.org-Event-Markup '
    || 'auf einer offiziellen Berlin.de-Seite, robots.txt wird vor jedem Fetch '
    || 'geprüft (siehe _shared/robots.ts).',
  'active',
  '{}'::jsonb
);
