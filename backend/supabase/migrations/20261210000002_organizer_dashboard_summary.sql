-- Veranstalterportal-Dashboard zeigte bislang nur Listen, keine einzige
-- Kennzahl (Nutzerfeedback: "Dashboard-Kennzahlen"). Eine schlanke,
-- datenschutzkonforme Summen-RPC nach demselben Muster wie
-- organizer_event_metrics (20261121000001) -- nur Summen über eigene
-- Events, keine Nutzer-IDs.
create or replace function organizer_dashboard_summary()
returns table (
  upcoming_events bigint,
  views_7d bigint,
  ticket_clicks_7d bigint
)
language sql
security definer
set search_path = public
stable
as $$
  with my_events as (
    select e.id, e.start_datetime
    from events e
    where exists (
      select 1 from entity_claims c
      where c.entity_type = 'organizer'
        and c.entity_id = e.organizer_id
        and c.user_id = auth.uid()
        and c.status = 'approved'
    )
  )
  select
    (select count(*) from my_events where start_datetime >= now()) as upcoming_events,
    (select count(*) from event_views ev join my_events e on e.id = ev.event_id where ev.viewed_at >= now() - interval '7 days') as views_7d,
    (select count(*) from ticket_clicks tc join my_events e on e.id = tc.event_id where tc.clicked_at >= now() - interval '7 days') as ticket_clicks_7d;
$$;

grant execute on function organizer_dashboard_summary() to authenticated;
