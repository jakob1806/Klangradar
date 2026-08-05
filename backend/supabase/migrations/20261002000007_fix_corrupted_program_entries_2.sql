-- Nachtrag zu 20261002000006: zwei bereits bekannte Fragment-Werke ("Konzert
-- f", "Tragische") saßen nicht auf einer Duplikat-Position (die andere
-- Werkzeile ihres jeweiligen Events hatte eine ANDERE position-Nummer), daher
-- hat sie die generische Duplikat-Bereinigung der Vormigration nicht erfasst.
-- Beide sind erwiesenermaßen Fließtext-Fragmente (siehe Kommentar dort) und
-- werden hier gezielt entfernt.
update events set references_checked_at = null
where id in (
  select event_id from event_works
  where work_id in (select id from works where title in ('Konzert f', 'Tragische'))
);

delete from event_works
where work_id in (select id from works where title in ('Konzert f', 'Tragische'));

delete from works where title in ('Konzert f', 'Tragische');
