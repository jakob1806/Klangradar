-- Rückwirkende Korrektur für die 73 bereits importierten Events der
-- mphil.de-Quelle (710e11e5-1241-4056-b839-400abf4c51e5), analog zur
-- Ursachenkorrektur in 20260909000007 + ingest-source/write.ts:
-- Mitwirkende-Verknüpfung nachtragen, Titel um den Orchesternamen
-- ergänzen, wo er nicht schon selbst enthalten ist (z.B. "New Year's Eve
-- concert" bleibt unverändert korrekt ohne Präfix zu brauchen — nein,
-- doch: enthält "philharmoniker"/"philharmonic" nicht, bekommt also auch
-- den Präfix, konsistent mit allen anderen).
insert into event_participants (event_id, ensemble_id, role)
select e.id, '00000000-0000-0000-0000-000000000301', null
from events e
where e.source_id = '710e11e5-1241-4056-b839-400abf4c51e5'
  and not exists (
    select 1 from event_participants ep
    where ep.event_id = e.id and ep.ensemble_id = '00000000-0000-0000-0000-000000000301'
  );

update events
set title = 'Münchner Philharmoniker: ' || title
where source_id = '710e11e5-1241-4056-b839-400abf4c51e5'
  and title not ilike '%philharmoniker%'
  and title not ilike '%philharmonic%';
