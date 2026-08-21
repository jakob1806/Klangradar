-- Liefert zusätzlich den konkreten Follow-Auslöser. Der Client kann damit
-- neben der gemischten „Gefolgt“-Rail ein erklärbares Entity-Spotlight wie
-- „Konzerte des Symphonieorchesters des Bayerischen Rundfunks“ bilden.
drop function if exists followed_events(int);

create function followed_events(p_result_limit int default 30)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[],
  follow_kind text, follow_name text
)
language sql stable security invoker
as $$
  select e.id, e.slug, e.title, e.subtitle, e.is_free,
    e.remaining_tickets_status, e.start_datetime, v.id,
    jsonb_build_object('name', v.name),
    coalesce((select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
      from event_genres eg join genres g on g.id=eg.genre_id where eg.event_id=e.id), '[]'::jsonb),
    e.image_urls,
    case when fv.venue_id is not null then 'venue'
         when fp.name is not null then 'person' else 'ensemble' end,
    coalesce(case when fv.venue_id is not null then v.name end, fp.name, fe.name)
  from events e
  join venues v on v.id=e.venue_id
  left join user_favorite_venues fv on fv.user_id=auth.uid() and fv.venue_id=e.venue_id
  left join lateral (
    select p.full_name as name from event_participants ep
    join user_favorite_persons f on f.user_id=auth.uid() and f.person_id=ep.person_id
    join persons p on p.id=ep.person_id where ep.event_id=e.id limit 1
  ) fp on true
  left join lateral (
    select en.name from event_participants ep
    join user_favorite_ensembles f on f.user_id=auth.uid() and f.ensemble_id=ep.ensemble_id
    join ensembles en on en.id=ep.ensemble_id where ep.event_id=e.id limit 1
  ) fe on true
  where auth.uid() is not null and e.status='scheduled' and e.start_datetime>=now()
    and (fv.venue_id is not null or fp.name is not null or fe.name is not null)
  order by e.start_datetime
  limit greatest(1, least(p_result_limit, 50));
$$;

grant execute on function followed_events(int) to anon, authenticated;
