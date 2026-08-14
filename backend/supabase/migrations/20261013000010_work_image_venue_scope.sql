-- Nutzervorgabe: manuell verknüpfte Werk-Bilder sollen wahlweise an eine
-- bestimmte Venue gebunden werden können (z.B. Zauberflöte NUR am
-- Nationaltheater) oder werkweit für jede Venue gelten (venue_id = null).
-- Nur bei origin_type='work' inhaltlich sinnvoll, aber bewusst ohne eigene
-- Check-Constraint dafür — images ist eine gemeinsame Tabelle für alle
-- Entitätstypen, die Spalte bleibt für andere origin_type einfach ungenutzt.
alter table images add column venue_id uuid references venues(id) on delete set null;

create index images_work_venue_idx on images (origin_type, origin_id, venue_id) where origin_type = 'work';
