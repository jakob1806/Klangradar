-- Erstellt von Claude Code (12.11.2026): Ensemble-Abos nur noch, wenn das
-- Ensemble wirklich das Abo prägt. Vorher reichte ein Gastauftritt mit
-- zwei Terminen desselben Programms (z. B. Tölzer Knabenchor in BRSO-Abo A/S).
create or replace function public.ensemble_subscriptions(p_ensemble_id uuid)
returns table (
  subscription_id uuid, organizer text, organizer_name text, code text, name text, season text, url text,
  upcoming int, next_start timestamptz, last_start timestamptz, image_url text, venue_name text, is_mine boolean
)
language sql stable security definer set search_path = public as $$
  with upcoming as (
    select es.subscription_id, e.id, e.title, e.start_datetime, e.image_urls[1] as image_url, v.name as venue_name,
      exists (select 1 from event_participants ep where ep.event_id = e.id and ep.ensemble_id = p_ensemble_id) as with_ensemble
    from event_concert_subscriptions es
    join events e on e.id = es.event_id
    left join venues v on v.id = e.venue_id
    where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')
  ),
  agg as (
    select u.subscription_id,
      count(*)::int as upcoming,
      count(*) filter (where u.with_ensemble)::int as with_ensemble,
      count(distinct lower(u.title)) filter (where u.with_ensemble)::int as ensemble_programs,
      min(u.start_datetime) as next_start,
      max(u.start_datetime) as last_start,
      (array_agg(u.image_url order by u.start_datetime) filter (where u.image_url is not null))[1] as image_url,
      mode() within group (order by u.venue_name) as venue_name
    from upcoming u
    group by u.subscription_id
  )
  select s.id, s.organizer, s.organizer_name, s.code, s.name, s.season, s.url,
    a.upcoming, a.next_start, a.last_start,
    coalesce(s.image_url, (select en.photo_url from ensembles en where en.id = p_ensemble_id), subscription_ensemble_photo(s.id), a.image_url),
    a.venue_name,
    exists (select 1 from user_concert_subscriptions m where m.subscription_id = s.id and m.user_id = auth.uid())
  from concert_subscriptions s
  join agg a on a.subscription_id = s.id
  where not s.hidden and s.merged_into is null
    -- mindestens zwei verschiedene Programme mit dem Ensemble und mindestens
    -- die Hälfte der Abo-Termine.
    and a.ensemble_programs >= 2 and a.with_ensemble * 2 >= a.upcoming
  order by a.next_start, s.name
  limit 20;
$$;
