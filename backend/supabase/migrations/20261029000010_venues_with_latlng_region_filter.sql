-- Fügt einen optionalen region_id-Filter zu venues_with_latlng() hinzu.
-- Notwendig geworden durch die Stadt-Erweiterung (20261029000003-000007):
-- ohne Filter zeigt die Karte jetzt alle ~165 Venues aus 5 Städten
-- gleichzeitig (siehe docs/12-city-expansion-import.md, Abschnitt
-- "Karten-Zentrierung"). Rückwärtskompatibel: p_region_id ist nullable und
-- defaultet auf null = alle Venues, identisches Verhalten wie bisher für
-- jeden Aufrufer, der den Parameter nicht kennt/nicht mitschickt.
-- Postgres behandelt venues_with_latlng() und venues_with_latlng(uuid) als
-- unterschiedliche Overloads (Argumentanzahl zählt, Default-Wert nicht) --
-- ohne den expliziten drop bliebe die alte parameterlose Funktion als
-- verwaistes Duplikat ohne Regions-Filter bestehen.
drop function if exists venues_with_latlng();

create or replace function venues_with_latlng(p_region_id uuid default null)
returns table (
  id uuid,
  slug text,
  name text,
  address_city text,
  lat float,
  lng float,
  upcoming_event_count bigint
)
language sql
stable
as $$
  select
    v.id, v.slug, v.name, v.address_city,
    ST_Y(v.location::geometry) as lat,
    ST_X(v.location::geometry) as lng,
    count(e.id) filter (
      where e.status = 'scheduled' and e.start_datetime >= now()
    ) as upcoming_event_count
  from venues v
  left join events e on e.venue_id = v.id
  where p_region_id is null or v.region_id = p_region_id
  group by v.id, v.slug, v.name, v.address_city, v.location;
$$;

grant execute on function venues_with_latlng(uuid) to anon, authenticated;
