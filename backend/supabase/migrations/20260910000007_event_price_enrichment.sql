-- Nutzeranfrage: "alle events zeigen nach wie vor 'preis auf anfrage' statt
-- einer preisspanne". DB-Check ergab: von 373 nicht-Entwurf-Events hatten
-- nur 7 price_min gesetzt — die Bulk-Ingestion-Parser (Schema.org/iCal/RSS/
-- Scrape) übernehmen nur, was die Quelle strukturiert mitliefert, ohne
-- Fallback-Recherche. price_checked_at analog zu profile_checked_at
-- (enrich-venue-details) / references_checked_at (enrich-event-references):
-- verhindert, dass Events ohne extrahierbaren Preis bei jedem Cron-Lauf
-- erneut ausgewählt werden und der Backfill nie konvergiert.
alter table events add column price_checked_at timestamptz;
