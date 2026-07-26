-- Phase 5 der Datenanreicherung (Nutzeranfrage zu Werken: "Instrumentierung,
-- ungefähre Dauer, Genre, alternative Titel und Satzfolge, wo verlässlich
-- verfügbar"). composer_id/catalog_number/key_signature/composition_year/
-- duration_minutes/genre/description_de existieren für works bereits; hier
-- nur die tatsächlich fehlenden Felder. profile_checked_at von Anfang an als
-- Auswahl-Gate (siehe Konvergenz-Bug bei enrich-venue-details) statt eines
-- Datenfelds.
alter table works add column instrumentation text;
alter table works add column alternative_titles text[];
alter table works add column movements text[];
alter table works add column profile_checked_at timestamptz;
