-- Abschnitt 2, reiner Konsistenz-Fix (kein Verhaltensunterschied): popular_events
-- sortierte bisher nach dem rohen Favoriten-Count, recommended_events()
-- (20260903000001) nutzt für denselben Signal-Anteil längst
-- ln(1 + favorites) (log-skaliert, siehe docs/08-home-feed-recommendation-
-- algorithm.md Abschnitt 4.1). Da popular_events ausschließlich nach genau
-- diesem einen Signal sortiert und ln() streng monoton ist, ändert das die
-- Zeilenreihenfolge NICHT — dient nur der Konsistenz, falls popular_events
-- künftig um ein zweites, additives Signal erweitert wird (dann wäre die
-- Log-Skalierung bereits vorhanden statt nachträglich migriert werden zu
-- müssen).
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
  venues jsonb,
  event_genres jsonb
)
language sql
stable
as $$
  select
    e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status, e.start_datetime,
    jsonb_build_object('name', v.name),
    coalesce(
      (
        select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
        from event_genres eg
        join genres g on g.id = eg.genre_id
        where eg.event_id = e.id
      ),
      '[]'::jsonb
    )
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
