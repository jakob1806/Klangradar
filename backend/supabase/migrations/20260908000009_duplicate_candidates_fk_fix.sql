-- Bug (live entdeckt, Screenshot: "update or delete on table events violates
-- foreign key constraint duplicate_candidates_event_b_id_fkey"): das
-- "Zusammenführen" in der Admin-Duplikate-Review markiert den Kandidaten
-- zuerst als status='merged' (event_b_id bleibt dabei unverändert stehen)
-- und löscht DANACH das events-Zeile mit id=event_b_id — der eigene
-- gerade erst aktualisierte duplicate_candidates-Datensatz verweist zu
-- diesem Zeitpunkt aber noch auf genau dieses Event, die FK (bisher ohne
-- ON DELETE-Klausel, also RESTRICT) blockiert die Löschung.
-- duplicate_candidates soll als Audit-Trail auch nach dem Löschen des
-- zusammengeführten Events erhalten bleiben — ON DELETE SET NULL statt
-- eines Cascade-Löschens des Kandidaten-Datensatzes selbst.
alter table duplicate_candidates
  drop constraint duplicate_candidates_event_a_id_fkey,
  add constraint duplicate_candidates_event_a_id_fkey
    foreign key (event_a_id) references events(id) on delete set null;

alter table duplicate_candidates
  drop constraint duplicate_candidates_event_b_id_fkey,
  add constraint duplicate_candidates_event_b_id_fkey
    foreign key (event_b_id) references events(id) on delete set null;
