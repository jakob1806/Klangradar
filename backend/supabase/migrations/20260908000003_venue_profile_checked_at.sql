-- Bug (live beim Backfill entdeckt): enrich-venue-details wählte Venues über
-- "history_de IS NULL" aus. Venues, deren offizielle Website keine
-- extrahierbare Geschichte hergibt, blieben dauerhaft history_de = NULL und
-- wurden dadurch bei JEDEM Lauf erneut ausgewählt, ohne dass der Backfill je
-- fertig wurde — 11 Batches à 5 Venues brachten nur 1 Venue von "pending" zu
-- "erledigt". Gleiches Funktionsprinzip wie references_checked_at bei
-- enrich-event-references: ein einmaliger Gate-Zeitstempel statt eines
-- Datenfelds als Auswahlkriterium.
alter table venues add column profile_checked_at timestamptz;
