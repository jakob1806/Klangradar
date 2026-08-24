-- Dauerhafte persönliche Home-Rails. Anders als entity_news_events (nur in
-- den letzten 3 Tagen angelegte Termine) liefert followed_events alle
-- kommenden Konzerte gefolgter Personen, Ensembles und Spielstätten in einer
-- gemeinsamen, chronologischen Liste.

create or replace function followed_events(p_result_limit int default 20)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[]
)
language sql stable security invoker
as $$
  select e.id, e.slug, e.title, e.subtitle, e.is_free,
    e.remaining_tickets_status, e.start_datetime, v.id,
    jsonb_build_object('name', v.name),
    coalesce((select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
      from event_genres eg join genres g on g.id=eg.genre_id where eg.event_id=e.id), '[]'::jsonb),
    e.image_urls
  from events e join venues v on v.id=e.venue_id
  where auth.uid() is not null and e.status='scheduled' and e.start_datetime>=now()
    and (
      exists(select 1 from user_favorite_venues f where f.user_id=auth.uid() and f.venue_id=e.venue_id)
      or exists(select 1 from event_participants ep join user_favorite_persons f on f.person_id=ep.person_id where ep.event_id=e.id and f.user_id=auth.uid())
      or exists(select 1 from event_participants ep join user_favorite_ensembles f on f.ensemble_id=ep.ensemble_id where ep.event_id=e.id and f.user_id=auth.uid())
    )
  order by e.start_datetime
  limit greatest(1, least(p_result_limit, 50));
$$;

create or replace function favorite_events_home(p_result_limit int default 20)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[]
)
language sql stable security invoker
as $$
  select e.id, e.slug, e.title, e.subtitle, e.is_free,
    e.remaining_tickets_status, e.start_datetime, v.id,
    jsonb_build_object('name', v.name),
    coalesce((select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
      from event_genres eg join genres g on g.id=eg.genre_id where eg.event_id=e.id), '[]'::jsonb),
    e.image_urls
  from favorites f join events e on e.id=f.event_id join venues v on v.id=e.venue_id
  where f.user_id=auth.uid() and e.status='scheduled' and e.start_datetime>=now()
  order by e.start_datetime
  limit greatest(1, least(p_result_limit, 50));
$$;

grant execute on function followed_events(int) to anon, authenticated;
grant execute on function favorite_events_home(int) to anon, authenticated;
