-- Phase 4 der Datenanreicherung (Nutzeranfrage: "Ausbildung, Karrierestationen,
-- künstlerischer Schwerpunkt, aktuelle relevante Rollen" für Personen bzw.
-- "Gründungsjahr, Mitglieder, Leitung, Residenzen, Repertoire" für Ensembles).
-- birth_date/death_date/nationality/awards/notable_recordings/
-- repertoire_highlights/biography_de existieren für persons bereits; hier nur
-- die tatsächlich fehlenden Felder. profile_checked_at von Anfang an als
-- Auswahl-Gate (siehe Konvergenz-Bug bei enrich-venue-details,
-- 20260908000003_venue_profile_checked_at.sql) statt eines Datenfelds, damit
-- der Backfill garantiert terminiert.
alter table persons add column education_career_de text;
alter table persons add column current_roles_de text;
alter table persons add column profile_checked_at timestamptz;

alter table ensembles add column leadership_de text;
alter table ensembles add column residency_de text;
alter table ensembles add column repertoire_de text;
alter table ensembles add column profile_checked_at timestamptz;
