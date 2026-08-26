-- Multi-City-Erweiterung, Abschnitt 4 "Serverseitige Abfragen".
--
-- search_all/venues_with_latlng/popular_events werden um p_city_id
-- erweitert, mit München als Default — bestehende Clients (die den neuen
-- Parameter noch nicht kennen/mitschicken) sehen dadurch exakt dieselben
-- Ergebnisse wie vor dieser Migration, statt plötzlich ungefilterte
-- Multi-City-Resultate zu bekommen ("bestehende Clients ... nicht sofort
-- beschädigen"). p_city_id => null bedeutet explizit "alle Städte" (z.B.
-- für zukünftige stadtübergreifende Admin-Ansichten).
--
-- Personen/Ensembles/Werke bleiben in search_all bewusst UNGEFILTERT
-- (stadtübergreifend, siehe Auftrag) — nur die event- und venue-Zeilen
-- werden nach Stadt gefiltert.
--
-- recommended_events/discovery_events werden hier NICHT angefasst: beide
-- wurden seit ihrer Einführung in vielen Migrationen (zuletzt u.a.
-- 20261016000012/15/21/23) mehrfach umgebaut und sind inzwischen sehr
-- groß/komplex. Ein blindes Nachbauen ihres kompletten aktuellen Bodies
-- ohne Testmöglichkeit in dieser Sandbox wäre ein zu hohes Regressions-
-- risiko für zentrale Home-Feed-Funktionen. Empfehlung: in einem
-- eigenen, fokussierten Folge-Schritt mit echter Testmöglichkeit (siehe
-- MIGRATION-Dokumentation) um p_city_id erweitern.
drop function if exists search_all(text, int);

create function search_all(q text, result_limit int default 8, p_city_id uuid default munich_city_id())
returns table (
  result_type text,
  id uuid,
  slug text,
  title text,
  subtitle text,
  score real,
  photo_url text,
  start_datetime timestamptz,
  price_min numeric,
  is_free boolean
)
language sql
stable
as $$
  with pattern as (select '%' || trim(q) || '%' as p, trim(q) as raw)
  (
    select distinct 'event'::text, e.id, e.slug, e.title,
           v.name || ' · ' || to_char(e.start_datetime at time zone 'Europe/Berlin', 'DD.MM.YYYY'),
           greatest(
             similarity(e.title, pattern.raw),
             coalesce((
               select max(similarity(w.title, pattern.raw))
               from event_works ew join works w on w.id = ew.work_id
               where ew.event_id = e.id
             ), 0),
             coalesce((
               select max(similarity(composer.full_name, pattern.raw))
               from event_works ew
               join works w on w.id = ew.work_id
               join persons composer on composer.id = w.composer_id
               where ew.event_id = e.id
             ), 0),
             coalesce((
               select max(similarity(coalesce(pp.full_name, en.name), pattern.raw))
               from event_participants ep
               left join persons pp on pp.id = ep.person_id
               left join ensembles en on en.id = ep.ensemble_id
               where ep.event_id = e.id
             ), 0)
           ),
           null::text,
           e.start_datetime,
           e.price_min,
           e.is_free
    from events e
    join venues v on v.id = e.venue_id
    cross join pattern
    where e.status != 'draft'
      and (p_city_id is null or e.city_id = p_city_id)
      and (
        e.title ilike pattern.p
        or e.subtitle ilike pattern.p
        or exists (
          select 1 from event_works ew join works w on w.id = ew.work_id
          where ew.event_id = e.id and w.title ilike pattern.p
        )
        or exists (
          select 1 from event_works ew
          join works w on w.id = ew.work_id
          join persons composer on composer.id = w.composer_id
          where ew.event_id = e.id and composer.full_name ilike pattern.p
        )
        or exists (
          select 1 from event_participants ep
          left join persons pp on pp.id = ep.person_id
          left join ensembles en on en.id = ep.ensemble_id
          where ep.event_id = e.id
            and (pp.full_name ilike pattern.p or en.name ilike pattern.p)
        )
      )
    order by 6 desc
    limit result_limit
  )
  union all
  (
    -- Personen bleiben stadtübergreifend durchsuchbar.
    select 'person', p.id, p.slug, p.full_name,
           array_to_string(p.roles::text[], ', '),
           similarity(p.full_name, pattern.raw),
           p.photo_url,
           null::timestamptz, null::numeric, null::boolean
    from persons p cross join pattern
    where p.full_name ilike pattern.p
    order by 6 desc
    limit result_limit
  )
  union all
  (
    -- Ensembles bleiben stadtübergreifend durchsuchbar.
    select 'ensemble', en.id, en.slug, en.name, en.type::text,
           similarity(en.name, pattern.raw),
           en.photo_url,
           null::timestamptz, null::numeric, null::boolean
    from ensembles en cross join pattern
    where en.name ilike pattern.p
    order by 6 desc
    limit result_limit
  )
  union all
  (
    select 'venue', ve.id, ve.slug, ve.name, ve.address_city,
           similarity(ve.name, pattern.raw),
           null::text,
           null::timestamptz, null::numeric, null::boolean
    from venues ve cross join pattern
    where ve.name ilike pattern.p
      and (p_city_id is null or ve.city_id = p_city_id)
    order by 6 desc
    limit result_limit
  )
  order by 6 desc;
$$;

grant execute on function search_all(text, int, uuid) to anon, authenticated;

-- venues_with_latlng: Karten-Tab nach Stadt filtern. p_city_id => null
-- bleibt "alle Städte" für künftige Übersichtskarten; alter Client ohne
-- Argument bekommt weiterhin nur München (bisheriges Verhalten).
drop function if exists venues_with_latlng();

create function venues_with_latlng(p_city_id uuid default munich_city_id())
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
  where p_city_id is null or v.id in (
    select venue_id from venues_in_city_region where region_city_id = p_city_id
  )
  group by v.id, v.slug, v.name, v.address_city, v.location;
$$;

grant execute on function venues_with_latlng(uuid) to anon, authenticated;

-- popular_events: Home-Feed-Modul nach Stadt.
drop function if exists popular_events(int);

create function popular_events(p_result_limit int default 10, p_city_id uuid default munich_city_id())
returns table (
  id uuid,
  slug text,
  title text,
  subtitle text,
  is_free boolean,
  remaining_tickets_status text,
  start_datetime timestamptz,
  venue_id uuid,
  venues jsonb,
  event_genres jsonb,
  image_urls text[]
)
language sql
stable
as $$
  select
    e.id, e.slug, e.title, e.subtitle, e.is_free,
    e.remaining_tickets_status, e.start_datetime, v.id,
    jsonb_build_object('id', v.id, 'name', v.name, 'photo_url', v.photo_url),
    coalesce(
      (
        select jsonb_agg(jsonb_build_object(
          'genres', jsonb_build_object('id', g.id, 'slug', g.slug, 'label_de', g.label_de)
        ))
        from event_genres eg
        join genres g on g.id = eg.genre_id
        where eg.event_id = e.id
      ),
      '[]'::jsonb
    ),
    e.image_urls
  from events e
  join venues v on v.id = e.venue_id
  left join (
    select event_id, count(*) as fav_count from favorites group by event_id
  ) fc on fc.event_id = e.id
  where e.status = 'scheduled' and e.start_datetime >= now()
    and (p_city_id is null or e.city_id = p_city_id)
  order by ln(1 + coalesce(fc.fav_count, 0)::float) desc, e.start_datetime
  limit p_result_limit;
$$;

grant execute on function popular_events(int, uuid) to anon, authenticated;
