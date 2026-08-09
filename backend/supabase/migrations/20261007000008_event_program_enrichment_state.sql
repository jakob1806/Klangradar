-- Die Referenzanreicherung markierte Events bislang auch dann dauerhaft als
-- geprüft, wenn der AI-Extraktor aus einer vorhandenen offiziellen Werkliste
-- kein einziges Werk lieferte. Ein eigener Programmstatus trennt deshalb die
-- allgemeine Referenzprüfung von der wiederholbaren Programmerkennung.

alter table events
  add column program_extraction_status text not null default 'pending'
    check (program_extraction_status in ('pending', 'complete', 'not_published', 'error')),
  add column program_check_attempts integer not null default 0,
  add column program_checked_at timestamptz,
  add column program_retry_after timestamptz,
  add column program_source_url text,
  add column program_last_error text;

-- Mehrere Aufführungstermine mit derselben program_id sollen in allen
-- Clients dieselben Werke sehen. Die native App konnte dies bisher nur beim
-- Lesen kompensieren; hier wird die Werkliste dauerhaft auf Geschwister-
-- termine übertragen, einschließlich Reihenfolge und Pause.
insert into event_works (event_id, work_id, position, after_intermission)
select target.id, source_works.work_id, source_works.position, source_works.after_intermission
from events target
join lateral (
  select ew.work_id, ew.position, ew.after_intermission
  from events source_event
  join event_works ew on ew.event_id = source_event.id
  where source_event.program_id = target.program_id
    and source_event.id <> target.id
  order by source_event.updated_at desc nulls last, source_event.id
) source_works on true
where target.program_id is not null
  and not exists (
    select 1 from event_works existing
    where existing.event_id = target.id
      and existing.work_id = source_works.work_id
      and existing.position = source_works.position
  )
on conflict do nothing;

update events e
set program_extraction_status = case
      when exists (select 1 from event_works ew where ew.event_id = e.id) then 'complete'
      else 'pending'
    end,
    program_checked_at = case
      when exists (select 1 from event_works ew where ew.event_id = e.id) then now()
      else null
    end,
    program_retry_after = null,
    program_last_error = null;

create index events_program_enrichment_queue_idx
  on events (program_retry_after, start_datetime)
  where status = 'scheduled' and program_extraction_status <> 'complete';
