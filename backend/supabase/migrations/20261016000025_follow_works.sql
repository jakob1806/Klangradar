-- Empfehlungssystem-Anfrage (Punkt 25, "Folgen als Kernfeature" —
-- "ggf. Komponisten/Werke"): Komponisten sind bereits persons-Datensätze
-- und damit über den bestehenden Personen-Follow abgedeckt. Für Werke
-- fehlte bisher nur die Push-Infrastruktur — user_favorite_works
-- (20261013000015) existierte schon als Empfehlungssignal (work_match in
-- recommended_events()), aber ohne notify_new_events-Spalte (analog zu
-- 20261016000010 bei Personen/Ensembles/Venues) gab es keinen Weg, bei
-- neuen Terminen eines gefolgten Werks benachrichtigt zu werden.
alter table user_favorite_works add column if not exists notify_new_events boolean not null default true;
