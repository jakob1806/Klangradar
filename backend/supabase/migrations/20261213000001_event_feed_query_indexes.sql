-- Feed-, Kalender- und Kartenabfragen nach Stadt, Status und Termin.
create index if not exists events_city_status_start_datetime_idx
  on public.events (city_id, status, start_datetime) where status = 'scheduled';
create index if not exists events_venue_status_start_datetime_idx
  on public.events (venue_id, status, start_datetime) where status = 'scheduled';
create index if not exists events_status_start_datetime_idx
  on public.events (status, start_datetime) where status = 'scheduled';
