-- Mehrfach-Bilder-Galerie für Personen/Ensembles (Nutzerwunsch: mehrere
-- Bilder pro Künstler/Ensemble hochladen, in der App durchwischbar, mit
-- redaktionell festgelegtem Querformat-Ausschnitt für die Detailansicht).
-- Baut auf der bestehenden images-Tabelle auf (Lizenz/Quelle/Qualität sind
-- dort schon vorhanden) statt einem zweiten Bild-System — schließt damit
-- auch die in der Architektur-Analyse gefundene "zwei parallele Media-
-- Repräsentationen"-Lücke für den Teil, der jetzt umgestellt wird.
--
-- sort_order statt einer separaten is_primary-Spalte: das Bild mit dem
-- niedrigsten sort_order je (origin_type, origin_id) IST das Titelbild/die
-- Miniaturansicht — ein einzelner Wahrheitsort statt zweier Felder, die
-- auseinanderlaufen könnten.
--
-- crop_* sind normalisierte Anteile (0..1) des Originalbilds für den
-- Querformat-Ausschnitt (16:9) in der App-Detailansicht — NULL bedeutet
-- "noch kein redaktioneller Zuschnitt", die App fällt dann auf einen
-- automatischen Center-Crop zurück (wie bisher).
alter table images add column sort_order int not null default 0;
alter table images add column crop_x numeric(5,4);
alter table images add column crop_y numeric(5,4);
alter table images add column crop_width numeric(5,4);
alter table images add column crop_height numeric(5,4);

create index images_origin_sort_idx on images(origin_type, origin_id, sort_order);
