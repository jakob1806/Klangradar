-- Datenschutzkonforme Veranstalter-Analytics: ausschließlich Summen pro
-- eigenem Event. Weder Nutzer-IDs noch Profile, Regionen oder Altersdaten
-- werden an Veranstalter ausgegeben.
create or replace function organizer_event_metrics()
returns table (
  event_id uuid,
  title text,
  start_datetime timestamptz,
  views bigint,
  saves bigint,
  shares bigint,
  ticket_clicks bigint
)
language sql
security definer
set search_path = public
stable
as $$
  select
    e.id as event_id,
    e.title,
    e.start_datetime,
    (select count(*) from event_views ev where ev.event_id = e.id) as views,
    (select count(*) from favorites f where f.event_id = e.id) as saves,
    (select count(*) from event_shares es where es.event_id = e.id) as shares,
    (select count(*) from ticket_clicks tc where tc.event_id = e.id) as ticket_clicks
  from events e
  where exists (
    select 1 from entity_claims c
    where c.entity_type = 'organizer'
      and c.entity_id = e.organizer_id
      and c.user_id = auth.uid()
      and c.status = 'approved'
  )
  order by e.start_datetime desc;
$$;

grant execute on function organizer_event_metrics() to authenticated;
