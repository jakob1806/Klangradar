-- Die letzte popular_events-Fassung verlor venue_id und image_urls. Die
-- native Home-Ansicht benötigt beides für korrekte Ortsnamen und Bilder.
drop function if exists popular_events(int);

create function popular_events(p_result_limit int default 10)
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
  order by ln(1 + coalesce(fc.fav_count, 0)::float) desc, e.start_datetime
  limit p_result_limit;
$$;

grant execute on function popular_events(int) to anon, authenticated;
