-- Fügt einen optionalen region_id-Filter zu search_all() hinzu.
-- Nutzerfeedback: "weder funktioniert das in der app ... noch funktioniert
-- die generelle differenzierung zwischen städten" — bisher filterte NUR
-- die Karte nach Stadt (siehe 20261029000010), Suche kannte
-- p_region_id gar nicht (siehe docs/12-city-expansion-import.md, Abschnitt
-- "Bekannte Einschränkung, nicht behoben").
--
-- Rückwärtskompatibel wie beim Karten-Filter: p_region_id ist nullable und
-- defaultet auf null = alle Städte, identisches Verhalten wie bisher für
-- jeden Aufrufer, der den Parameter nicht kennt/nicht mitschickt.
-- Postgres behandelt search_all(text, int) und search_all(text, int, uuid)
-- als unterschiedliche Overloads -- ohne den expliziten drop bliebe die
-- alte Drei-Parameter-lose Funktion als verwaistes Duplikat ohne
-- Regions-Filter bestehen.
drop function if exists search_all(text, int);

create function search_all(q text, result_limit int default 8, p_region_id uuid default null)
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
      and (p_region_id is null or v.region_id = p_region_id)
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
      and (p_region_id is null or ve.region_id = p_region_id)
    order by 6 desc
    limit result_limit
  )
  order by 6 desc;
$$;

grant execute on function search_all(text, int, uuid) to anon, authenticated;
