-- Schaltet Berlin, Hamburg, Frankfurt am Main und Wien live (is_active=true),
-- auf explizite Nutzeranfrage — VOR redaktioneller Bildfreigabe, ohne
-- Event-Ingestion und ohne dass die 6 in 20261101000011-000014 als
-- "lowercase-gebrandet" markierten Ensemblenamen jemals gegengeprüft
-- wurden. Siehe docs/12-city-expansion-import.md für den vollständigen
-- Stand/die bekannten Lücken zum Zeitpunkt dieser Freischaltung.
update regions
set is_active = true
where slug in ('berlin', 'hamburg', 'frankfurt', 'vienna', 'berlin-land', 'hamburg-land', 'hessen', 'wien-land', 'at');
