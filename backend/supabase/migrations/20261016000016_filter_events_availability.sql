-- Ticket Intelligence (Nutzeranfrage): "Ticketdaten in Suche, Filter und
-- Empfehlungen integrieren" — filter_events() bekommt einen Verfügbarkeits-
-- Filter (analog zu p_accessible_only/p_open_air_only). Bewusst ein
-- einzelnes Boolean statt eines Status-Enum-Parameters: die Suche/Filter-UI
-- braucht praktisch nur "zeig mir, was ich noch kaufen kann" — "sold_out"
-- und "box_office_only" sind beides Fälle, in denen der reguläre Vorverkauf
-- nicht mehr möglich ist.
drop function if exists filter_events(uuid[], timestamptz, timestamptz, numeric, boolean, boolean, float);

create function filter_events(
  p_genre_ids uuid[] default null,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null,
  p_max_price numeric default null,
  p_accessible_only boolean default false,
  p_open_air_only boolean default false,
  p_max_distance_km float default null,
  p_available_only boolean default false
)
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
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_home geography;
begin
  if p_max_distance_km is not null then
    select home_location into v_home from profiles where profiles.id = auth.uid();
    if v_home is null then
      raise exception 'Kein Standort hinterlegt — bitte im Profil oder beim Onboarding festlegen.';
    end if;
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
      e.image_urls
    from events e
    join venues v on v.id = e.venue_id
    where e.status = 'scheduled'
      and (
        p_genre_ids is null
        or exists (
          select 1 from event_genres eg
          where eg.event_id = e.id and eg.genre_id = any(p_genre_ids)
        )
      )
      and (p_date_from is null or e.start_datetime >= p_date_from)
      and (p_date_to is null or e.start_datetime < p_date_to)
      and (p_max_price is null or e.price_min <= p_max_price or e.is_free)
      and (not p_accessible_only or coalesce((e.accessibility->>'wheelchair')::boolean, false))
      and (not p_open_air_only or e.is_open_air)
      and (p_max_distance_km is null or ST_DWithin(v.location, v_home, p_max_distance_km * 1000))
      and (not p_available_only or e.remaining_tickets_status is distinct from 'sold_out')
    order by e.start_datetime
    limit 50;
end;
$$;

grant execute on function filter_events(uuid[], timestamptz, timestamptz, numeric, boolean, boolean, float, boolean) to anon, authenticated;
