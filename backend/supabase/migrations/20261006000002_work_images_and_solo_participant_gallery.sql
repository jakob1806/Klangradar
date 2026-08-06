-- Nutzerwunsch: Werke sollen wie Personen/Venues/Ensembles/Events über die
-- Admin-Bilderrecherche (KI-Suche, Link, manueller Upload) ein eigenes Bild/
-- eine Galerie bekommen können (research-entity-image/index.ts, neuer
-- entityType "work"). images.origin_type erlaubte "work" bisher nicht.
alter table images drop constraint images_origin_type_check;
alter table images add constraint images_origin_type_check
  check (origin_type in ('event', 'venue', 'ensemble', 'person', 'organizer', 'festival', 'work'));
