-- Multi-City-Erweiterung, Abschnitt 4: "kommende Events nach Stadt" und
-- "Kalender nach Stadt und Monat" als neue, eigenständige RPCs statt in
-- die bestehenden, mehrfach gewachsenen Home-Feed-RPCs einzugreifen.
--
-- Bisher lief die native/Flutter "kommende Events"-Abfrage laut
-- Migrationshistorie als reine PostgREST-select-Abfrage direkt gegen
-- `events` (kein RPC) — das funktioniert nach dieser Migration unverändert
-- weiter (events.city_id ist jetzt einfach ein zusätzlich filterbares
-- Feld). Diese RPCs sind für Fälle gedacht, die eine serverseitige
-- Aggregation/Sortierung brauchen, die ein reiner PostgREST-Filter nicht
-- leisten kann.
create function upcoming_events_by_city(
  p_city_id uuid,
  p_result_limit int default 50,
  p_offset int default 0
)
returns setof events
language sql
stable
as $$
  select e.* from events e
  where e.city_id = p_city_id
    and e.status = 'scheduled'
    and e.start_datetime >= now()
  order by e.start_datetime, e.id
  limit p_result_limit offset p_offset;
$$;

grant execute on function upcoming_events_by_city(uuid, int, int) to anon, authenticated;

-- Kalender: alle Events einer Stadt in einem Kalendermonat (Client-Zeitzone
-- der Stadt wird über regions.timezone aufgelöst, nicht hart 'Europe/Berlin'
-- angenommen — relevant für künftige Nicht-DACH-Städte).
create function calendar_events_by_city(
  p_city_id uuid,
  p_year int,
  p_month int
)
returns setof events
language plpgsql
stable
as $$
declare
  v_tz text;
  v_start timestamptz;
  v_end timestamptz;
begin
  select timezone into v_tz from regions where id = p_city_id;
  v_tz := coalesce(v_tz, 'Europe/Berlin');
  v_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0, v_tz);
  v_end := v_start + interval '1 month';

  return query
    select e.* from events e
    where e.city_id = p_city_id
      and e.status = 'scheduled'
      and e.start_datetime >= v_start
      and e.start_datetime < v_end
    order by e.start_datetime, e.id;
end;
$$;

grant execute on function calendar_events_by_city(uuid, int, int) to anon, authenticated;

-- "Heute in deiner Nähe": heutige Events einer Stadt, nächstgelegene
-- zuerst (nutzt den bestehenden events_nearby-Ansatz, aber city-gefiltert
-- statt reiner Umkreissuche, damit z.B. ein Nutzer am Stadtrand nicht
-- plötzlich Events der Nachbarstadt sieht, nur weil sie geografisch näher
-- liegen).
create function events_today_by_city(p_city_id uuid)
returns setof events
language plpgsql
stable
as $$
declare
  v_tz text;
begin
  select timezone into v_tz from regions where id = p_city_id;
  v_tz := coalesce(v_tz, 'Europe/Berlin');

  return query
    select e.* from events e
    where e.city_id = p_city_id
      and e.status = 'scheduled'
      and e.start_datetime >= date_trunc('day', now() at time zone v_tz) at time zone v_tz
      and e.start_datetime < (date_trunc('day', now() at time zone v_tz) + interval '1 day') at time zone v_tz
    order by e.start_datetime, e.id;
end;
$$;

grant execute on function events_today_by_city(uuid) to anon, authenticated;

-- Inspirationskategorien nach Stadt: editorial_collections.city_id ist
-- optional (null = stadtübergreifend) — eine Sammlung erscheint also in
-- jeder Stadt, sofern sie nicht explizit auf eine bestimmte Stadt
-- eingeschränkt wurde.
create function editorial_collections_by_city(p_city_id uuid)
returns setof editorial_collections
language sql
stable
as $$
  select c.* from editorial_collections c
  where c.is_published
    and (c.city_id is null or c.city_id = p_city_id)
  order by c.sort_order, c.title;
$$;

grant execute on function editorial_collections_by_city(uuid) to anon, authenticated;

-- Karten-Venues nach Stadt inkl. Konzertregion-Nachbarorte (siehe
-- venues_in_city_region aus 20261030000003_city_area_membership.sql).
create function map_venues_by_city(p_city_id uuid)
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
  join venues_in_city_region vic on vic.venue_id = v.id and vic.region_city_id = p_city_id
  left join events e on e.venue_id = v.id
  group by v.id, v.slug, v.name, v.address_city, v.location;
$$;

grant execute on function map_venues_by_city(uuid) to anon, authenticated;

-- Gefolgte Personen/Ensembles innerhalb der aktiven Stadt: Follows selbst
-- bleiben stadtübergreifend (Tabellen user_favorite_persons/_ensembles
-- unverändert), aber ihre KOMMENDEN EVENTS lassen sich pro Stadt abfragen.
create function followed_entity_events_by_city(p_user_id uuid, p_city_id uuid)
returns setof events
language sql
stable
as $$
  select distinct e.* from events e
  where e.city_id = p_city_id
    and e.status = 'scheduled'
    and e.start_datetime >= now()
    and (
      exists (
        select 1 from event_participants ep
        join user_favorite_persons ufp on ufp.person_id = ep.person_id
        where ep.event_id = e.id and ufp.user_id = p_user_id
      )
      or exists (
        select 1 from event_participants ep
        join user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
        where ep.event_id = e.id and ufe.user_id = p_user_id
      )
    )
  order by e.start_datetime;
$$;

grant execute on function followed_entity_events_by_city(uuid, uuid) to authenticated;
