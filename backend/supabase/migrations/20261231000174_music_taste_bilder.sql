-- Erstellt von Claude Code (13.11.2026): Musikgeschmack – Bilder überall:
-- „Das hörst du“ mit Foto, aktuelle Fotos für Personen/Ensembles, Werke mit
-- Komponistenfoto, Spielstätten mit Foto, Konzerte ohne Bild mit Spielstättenfoto.
create or replace function public.music_taste_recommendations(p_city_id uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with prof as (select * from music_taste_profiles where user_id = auth.uid()),
  pids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'persons') x),
  eids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'ensembles') x),
  wids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'works') x),
  upcoming as (
    select e.id, e.slug, e.title, e.start_datetime, coalesce(e.image_urls[1], v.photo_url) as image_url, v.name as venue, v.id as venue_id, v.photo_url as venue_photo,
           coalesce(e.city_id, v.city_id) as city_id
    from events e left join venues v on v.id = e.venue_id
    where e.start_datetime > now() and e.status not in ('draft', 'cancelled')
  ),
  hits as (
    select ep.event_id, p.s, pe.full_name as reason from event_participants ep join pids p on p.id = ep.person_id join persons pe on pe.id = p.id
    union all
    select ep.event_id, x.s, en.name from event_participants ep join eids x on x.id = ep.ensemble_id join ensembles en on en.id = x.id
    union all
    select ew.event_id, x.s * 1.5, wo.title from event_works ew join wids x on x.id = ew.work_id join works wo on wo.id = x.id
    union all
    select ew.event_id, p.s, pe.full_name from event_works ew join works wo on wo.id = ew.work_id join pids p on p.id = wo.composer_id join persons pe on pe.id = p.id
  ),
  scored as (
    select u.*, sum(h.s)
             * (1 + 0.25 * (count(distinct h.reason) - 1))
             * (case when u.start_datetime < now() + interval '8 weeks' then 1.3 else 1 end) as score,
           (array_agg(distinct h.reason))[1:3] as reasons
    from upcoming u join hits h on h.event_id = u.id
    group by u.id, u.slug, u.title, u.start_datetime, u.image_url, u.venue, u.venue_id, u.venue_photo, u.city_id
  ),
  ev_city as (
    select * from scored where p_city_id is null or city_id = p_city_id
    order by score desc, start_datetime limit 40
  ),
  -- Wenig Treffer: passende Genres in der Stadt (nächste 8 Wochen).
  genre_ev as (
    select u.*, 0.1::numeric as score, array['Passt zu deinen Genres']::text[] as reasons
    from upcoming u
    where (select count(*) from ev_city) < 5
      and (p_city_id is null or u.city_id = p_city_id)
      and u.start_datetime < now() + interval '8 weeks'
      and u.id not in (select id from ev_city)
      and exists (select 1 from event_genres eg join genres g on g.id = eg.genre_id
                  where eg.event_id = u.id and g.slug::text = any(music_taste_genre_slugs((select matches->'genres' from prof))))
    order by u.start_datetime limit 10
  ),
  ev as (select * from ev_city union all select * from genre_ev),
  other_city as (
    select count(*) as n, (select r.name from scored s2 join regions r on r.id = s2.city_id
                           where p_city_id is not null and s2.city_id is distinct from p_city_id
                           group by r.name order by count(*) desc limit 1) as city
    from scored where p_city_id is not null and city_id is distinct from p_city_id
  ),
  -- Anzahl kommender Konzerte (in der Stadt) je Person / Ensemble.
  person_up as (
    select ep.person_id id, count(distinct u.id) n from event_participants ep join upcoming u on u.id = ep.event_id
    where (p_city_id is null or u.city_id = p_city_id) and ep.person_id in (select id from pids) group by ep.person_id
    union all
    select wo.composer_id, count(distinct u.id) from event_works ew join works wo on wo.id = ew.work_id join upcoming u on u.id = ew.event_id
    where (p_city_id is null or u.city_id = p_city_id) and wo.composer_id in (select id from pids) group by wo.composer_id
  ),
  ensemble_up as (
    select ep.ensemble_id id, count(distinct u.id) n from event_participants ep join upcoming u on u.id = ep.event_id
    where (p_city_id is null or u.city_id = p_city_id) and ep.ensemble_id in (select id from eids) group by ep.ensemble_id
  )
  select case when not exists (select 1 from prof) then null else jsonb_build_object(
    'providers', (select to_jsonb(providers) from prof),
    'updated_at', (select updated_at from prof),
    'period', (select matches->'period' from prof),
    'genres', (select matches->'genres' from prof),
    'artist_count', (select matches->'artist_count' from prof),
    'track_count', (select matches->'track_count' from prof),
    'top_tracks', (select coalesce(matches->'top_tracks', '[]') from prof),
    'listened', coalesce((select jsonb_agg(l || jsonb_build_object(
        'photo_url', coalesce((select photo_url from persons where id = (l->>'person_id')::uuid),
                              (select photo_url from ensembles where id = (l->>'ensemble_id')::uuid)),
        'upcoming',
        coalesce((select sum(n) from person_up where id = (l->>'person_id')::uuid), 0)
        + coalesce((select sum(n) from ensemble_up where id = (l->>'ensemble_id')::uuid), 0)))
      from prof, jsonb_array_elements(coalesce(prof.matches->'listened', '[]')) l), '[]'),
    'persons', coalesce((select jsonb_agg(x || jsonb_build_object(
        'photo_url', (select coalesce(p.photo_url, x->>'photo_url') from persons p where p.id = (x->>'id')::uuid),
        'upcoming', coalesce((select sum(n) from person_up where id = (x->>'id')::uuid), 0)))
      from prof, jsonb_array_elements(prof.matches->'persons') x), '[]'),
    'ensembles', coalesce((select jsonb_agg(x || jsonb_build_object(
        'photo_url', (select coalesce(e.photo_url, x->>'photo_url') from ensembles e where e.id = (x->>'id')::uuid),
        'upcoming', coalesce((select sum(n) from ensemble_up where id = (x->>'id')::uuid), 0)))
      from prof, jsonb_array_elements(prof.matches->'ensembles') x), '[]'),
    'works', coalesce((select jsonb_agg(x || jsonb_build_object('photo_url',
        (select p.photo_url from works w join persons p on p.id = w.composer_id where w.id = (x->>'id')::uuid)))
      from prof, jsonb_array_elements(coalesce(prof.matches->'works', '[]')) x), '[]'),
    'events', coalesce((select jsonb_agg(to_jsonb(ev) order by ev.score desc, ev.start_datetime) from ev), '[]'),
    'venues', coalesce((select jsonb_agg(to_jsonb(x)) from (
       select ev.venue_id as id, ev.venue as title, max(ev.venue_photo) as photo_url, count(*) as event_count from ev where ev.venue_id is not null
       group by ev.venue_id, ev.venue order by count(*) desc limit 10) x), '[]'),
    'other_city_count', (select n from other_city),
    'other_city', (select city from other_city)
  ) end;
$$;
grant execute on function public.music_taste_recommendations(uuid) to authenticated;
