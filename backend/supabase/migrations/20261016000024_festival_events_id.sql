-- Empfehlungssystem-Anfrage (Punkt 25, "Folgen als Kernfeature"): festival_
-- events() gab bisher nur festival_name zurück, kein festival_id — ohne ID
-- kann der Client keinen Folgen-Button für das aktive Festival anbieten
-- (user_favorite_festivals.festival_id braucht die ID, nicht den Namen).
drop function if exists festival_events(int);

create function festival_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[],
  festival_name text, festival_id uuid
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_festival_id uuid;
  v_festival_name text;
begin
  select f.id, f.name into v_festival_id, v_festival_name
  from festivals f
  where f.start_date is not null and f.end_date is not null
    and current_date between f.start_date and f.end_date
  order by f.end_date asc
  limit 1;

  if v_festival_id is null then
    return;
  end if;

  return query
    select
      e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status, e.start_datetime,
      v.id,
      jsonb_build_object('name', v.name),
      coalesce(
        (
          select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
          from event_genres eg
          join genres g on g.id = eg.genre_id
          where eg.event_id = e.id
        ),
        '[]'::jsonb
      ),
      e.image_urls,
      v_festival_name,
      v_festival_id
    from events e
    join venues v on v.id = e.venue_id
    where e.festival_id = v_festival_id
      and e.status = 'scheduled'
      and e.start_datetime >= now()
    order by e.start_datetime
    limit p_result_limit;
end;
$$;

grant execute on function festival_events(int) to anon, authenticated;
