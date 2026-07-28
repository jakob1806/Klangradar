-- search_all() liefert bisher kein Bild mit — die Künstlerliste im Suchtab
-- (App: search_screen.dart, _ResultsList) kann deshalb nur ein generisches
-- Typ-Icon statt eines Miniaturbilds zeigen (Nutzerfeedback: "unter der
-- Liste der Künstler ... sieht man die Miniaturbilder der Künstler nicht").
-- Bewusst nur für 'person' befüllt (die tatsächliche Beschwerde) — für
-- event/ensemble/venue bleibt die Spalte null, keine Verhaltensänderung
-- dort, kein Anfassen der image_urls[]-Array-Konvention bei Events.
-- CREATE OR REPLACE reicht nicht, sobald sich die Return-Spaltenliste
-- ändert (neue OUT-Spalte photo_url) — Postgres verlangt dafür einen
-- expliziten DROP.
drop function if exists search_all(text, int);

create function search_all(q text, result_limit int default 8)
returns table (
  result_type text,
  id uuid,
  slug text,
  title text,
  subtitle text,
  score real,
  photo_url text
)
language sql
stable
as $$
  with pattern as (select '%' || trim(q) || '%' as p, trim(q) as raw)
  (
    select 'event'::text, e.id, e.slug, e.title,
           v.name || ' · ' || to_char(e.start_datetime at time zone 'Europe/Berlin', 'DD.MM.YYYY'),
           similarity(e.title, pattern.raw),
           null::text
    from events e
    join venues v on v.id = e.venue_id
    cross join pattern
    where e.status != 'draft'
      and (e.title ilike pattern.p or e.subtitle ilike pattern.p)
    order by 6 desc
    limit result_limit
  )
  union all
  (
    select 'person', p.id, p.slug, p.full_name,
           array_to_string(p.roles::text[], ', '),
           similarity(p.full_name, pattern.raw),
           p.photo_url
    from persons p cross join pattern
    where p.full_name ilike pattern.p
    order by 6 desc
    limit result_limit
  )
  union all
  (
    select 'ensemble', en.id, en.slug, en.name, en.type::text,
           similarity(en.name, pattern.raw),
           null::text
    from ensembles en cross join pattern
    where en.name ilike pattern.p
    order by 6 desc
    limit result_limit
  )
  union all
  (
    select 'venue', ve.id, ve.slug, ve.name, ve.address_city,
           similarity(ve.name, pattern.raw),
           null::text
    from venues ve cross join pattern
    where ve.name ilike pattern.p
    order by 6 desc
    limit result_limit
  )
  order by 6 desc;
$$;

grant execute on function search_all(text, int) to anon, authenticated;
