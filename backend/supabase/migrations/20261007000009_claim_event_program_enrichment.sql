-- Atomisches Claiming erlaubt mehrere kleine Edge-Batches parallel, ohne
-- dieselben Events doppelt zu verarbeiten. Ein abgebrochener Worker wird
-- nach 15 Minuten automatisch wieder freigegeben.

alter table events drop constraint events_program_extraction_status_check;
alter table events add constraint events_program_extraction_status_check
  check (program_extraction_status in ('pending', 'processing', 'complete', 'not_published', 'error'));

create or replace function claim_event_program_enrichment(p_limit integer default 5)
returns setof events
language sql
security definer
set search_path = public
as $$
  with picked as (
    select id
    from events
    where status = 'scheduled'
      and start_datetime >= now()
      and (
        program_extraction_status = 'pending'
        or (
          program_extraction_status in ('not_published', 'error', 'processing')
          and (program_retry_after is null or program_retry_after <= now())
        )
      )
    order by start_datetime asc
    for update skip locked
    limit greatest(1, least(p_limit, 50))
  )
  update events e
  set program_extraction_status = 'processing',
      program_checked_at = now(),
      program_retry_after = now() + interval '15 minutes'
  from picked
  where e.id = picked.id
  returning e.*;
$$;

revoke all on function claim_event_program_enrichment(integer) from public, anon, authenticated;
grant execute on function claim_event_program_enrichment(integer) to service_role;
