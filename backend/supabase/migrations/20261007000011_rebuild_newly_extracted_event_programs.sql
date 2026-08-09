-- Die erste Version der neuen Extraktion nutzte den fokussierten offiziellen
-- Programmblock nur, wenn der allgemeine Extraktor gar kein Werk lieferte.
-- Ein abgeschnittenes Einzelwerk konnte dadurch eine vollständige Liste
-- verdrängen. Nur die in diesem Backfill neu aufgebauten Programme erneut
-- freigeben; redaktionelle und ältere Werkzuordnungen bleiben unangetastet.

delete from event_works ew
using events e
where ew.event_id = e.id
  and e.status = 'scheduled'
  and e.start_datetime >= now()
  and e.program_extraction_status = 'complete'
  and e.program_check_attempts > 0
  and e.program_source_url is not null;

update events
set program_extraction_status = 'pending',
    program_retry_after = null,
    program_last_error = null
where status = 'scheduled'
  and start_datetime >= now()
  and program_check_attempts > 0
  and program_source_url is not null;

update events
set program_retry_after = null
where status = 'scheduled'
  and start_datetime >= now()
  and program_extraction_status = 'error';
