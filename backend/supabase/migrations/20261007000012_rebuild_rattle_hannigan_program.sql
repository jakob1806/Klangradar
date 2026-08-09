-- Dieser Programmverbund enthielt bereits vor Einführung des neuen
-- Programmstatus einen abgeschnittenen Werktitel und wurde deshalb beim
-- allgemeinen Backfill fälschlich als vollständig übersprungen.
delete from event_works ew
using events e
where ew.event_id = e.id
  and e.title ilike '%Barbara Hannigan%';

update events
set program_extraction_status = 'pending',
    program_retry_after = null,
    program_last_error = null,
    program_source_url = null
where title ilike '%Barbara Hannigan%';
