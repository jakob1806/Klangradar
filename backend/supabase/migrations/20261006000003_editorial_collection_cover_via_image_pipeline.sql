-- Nutzerwunsch: Das Titelbild redaktioneller Sammlungen soll wie bei
-- Personen/Venues/Ensembles/Werken über die Bilder-Pipeline laufen (KI-
-- Recherche/Link/Upload) statt als roh eingetipptes URL-Feld — dasselbe
-- Hotlink-Zuverlässigkeitsproblem, das dort schon gefixt wurde.
alter table images drop constraint images_origin_type_check;
alter table images add constraint images_origin_type_check
  check (origin_type in ('event', 'venue', 'ensemble', 'person', 'organizer', 'festival', 'work', 'editorial_collection'));
