-- Nach dem gezielten Titel-Rebuild die beiden Termine noch einmal freigeben,
-- damit auch die nun deterministisch aus der offiziellen Liste gelesenen
-- Komponisten verlinkt werden.
delete from event_works ew
using events e
where ew.event_id = e.id
  and e.title ilike '%Barbara Hannigan%';

update events
set program_extraction_status = 'pending',
    program_retry_after = null,
    program_last_error = null
where title ilike '%Barbara Hannigan%';
