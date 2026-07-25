-- Auf Nutzerwunsch: vollautomatische Bildversorgung für Events/Venues/
-- Personen/Ensembles/Festivals, inkl. automatischer Erkennung und Ersetzung
-- bestehender kaputter/leerer Bilder (siehe enrich-entity-images/index.ts,
-- komplett überarbeitet in derselben PR). Ein Health-Check-Durchlauf prüft
-- bestehende photo_url/image_urls auf Erreichbarkeit — ohne eine
-- "zuletzt geprüft"-Spalte würde dieselbe kleine Teilmenge (die mit dem
-- niedrigsten id-Sortierwert) bei jedem Cron-Lauf erneut geprüft, während
-- der Rest nie an die Reihe käme. photo_checked_at (nulls first sortiert,
-- nach jeder Prüfung auf now() gesetzt) sorgt für einen fairen Umlauf über
-- alle Zeilen mit gesetztem photo_url.
alter table venues add column photo_checked_at timestamptz;
alter table persons add column photo_checked_at timestamptz;
alter table ensembles add column photo_checked_at timestamptz;
alter table festivals add column photo_checked_at timestamptz;
-- Events haben image_urls (Array) statt einer einzelnen photo_url-Spalte,
-- daher ein eigener, gleich benannter Spaltentyp statt Wiederverwendung.
alter table events add column images_checked_at timestamptz;
