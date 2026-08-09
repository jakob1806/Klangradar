-- Nutzervorgabe: Personen brauchen strukturierte Namensfelder (Vorname,
-- zweiter Vorname, Nachname) statt nur eines Freitext-Namens im Admin —
-- und Personen/Ensembles brauchen einen eigenen, runden Foto-Ausschnitt
-- (Fokuspunkt fürs Avatar-Bild), unabhängig vom bestehenden 16:9-
-- Galerie-Crop auf der images-Tabelle.
--
-- full_name bleibt bewusst bestehen und NOT NULL — es ist die einzige
-- Quelle für Fuzzy-Matching (find_matching_person), Duplikat-Auflösung
-- (resolve-person-duplicates), Volltextsuche (search_vector) und
-- Sortierung in Admin/Flutter-App/nativer App. Diese drei neuen Spalten
-- sind rein additiv fürs Admin-Formular; das Admin schreibt full_name
-- weiterhin selbst (aus den drei Teilen zusammengesetzt), alle
-- bestehenden Lesepfade bleiben unverändert.
alter table persons add column first_name text;
alter table persons add column middle_name text;
alter table persons add column last_name text;

-- Avatar-Crop: eigene Spalten statt der images-Tabelle, weil der
-- Ausschnitt zum einzelnen Legacy-photo_url-Feld gehört (nicht zur
-- images-Galerie) und konzeptionell unabhängig vom dortigen 16:9-Crop
-- desselben Fotos ist. Gleiche Anteils-Konvention (0..1) wie
-- images.crop_x/y/width/height (siehe 20260909000006). NULL = kein
-- redaktioneller Ausschnitt gewählt, App fällt auf automatisches
-- zentriertes BoxFit.cover zurück (unverändertes bisheriges Verhalten).
alter table persons add column avatar_crop_x numeric(5, 4);
alter table persons add column avatar_crop_y numeric(5, 4);
alter table persons add column avatar_crop_width numeric(5, 4);
alter table persons add column avatar_crop_height numeric(5, 4);

alter table ensembles add column avatar_crop_x numeric(5, 4);
alter table ensembles add column avatar_crop_y numeric(5, 4);
alter table ensembles add column avatar_crop_width numeric(5, 4);
alter table ensembles add column avatar_crop_height numeric(5, 4);
