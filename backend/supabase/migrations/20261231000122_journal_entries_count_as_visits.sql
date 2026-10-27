-- Erstellt von Claude Code (Nutzerwunsch 27.10.2026): selbst eingetragene
-- Konzerte (user_concert_entries, Konzert-Journal) zählen wie besuchte
-- Konzerte – im Besuchszähler (my_klangradar_stats), im Jahresrückblick
-- "Dein Konzertjahr" (my_concert_year) und in der Profilkennzahl für
-- Freunde (user_profile). Nur vergangene Einträge (starts_at <= now()).
-- Level/XP/Achievements rechnet die App aus derselben Besuchsliste.

create or replace function public.my_klangradar_stats()
returns jsonb
language sql
stable
security invoker
as $$
  select jsonb_build_object(
    'saved_events', (select count(*) from favorites where user_id = auth.uid()),
    'planned_events', (
      select count(*) from favorites f
      join events e on e.id = f.event_id
      where f.user_id = auth.uid() and f.status = 'attending' and e.start_datetime >= now()
    ),
    'visited_events',
      (select count(*) from public.event_attendance where user_id = auth.uid() and status = 'attended')
      + (select count(*) from public.user_concert_entries where user_id = auth.uid() and starts_at <= now()),
    'followed_persons', (select count(*) from user_favorite_persons where user_id = auth.uid()),
    'followed_ensembles', (select count(*) from user_favorite_ensembles where user_id = auth.uid()),
    'followed_venues', (select count(*) from user_favorite_venues where user_id = auth.uid()),
    'followed_works', (select count(*) from public.user_favorite_works where user_id = auth.uid())
  );
$$;
grant execute on function public.my_klangradar_stats() to authenticated;

create or replace function public.my_concert_year(p_year int default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_year int := coalesce(p_year, extract(year from now())::int);
  v_from timestamptz := make_timestamptz(v_year, 1, 1, 0, 0, 0, 'Europe/Berlin');
  v_to timestamptz := make_timestamptz(v_year + 1, 1, 1, 0, 0, 0, 'Europe/Berlin');
  v_result jsonb;
begin
  if auth.uid() is null then return '{}'::jsonb; end if;
  with attended as (
    select e.id, e.slug, e.title, e.start_datetime, e.end_datetime, e.duration_minutes, e.venue_id from events e
     where e.start_datetime >= v_from and e.start_datetime < v_to and e.start_datetime <= now()
       and (exists (select 1 from event_attendance a where a.event_id = e.id and a.user_id = auth.uid())
            or exists (select 1 from event_ratings r where r.event_id = e.id and r.user_id = auth.uid())
            or exists (select 1 from favorites f where f.event_id = e.id and f.user_id = auth.uid() and f.status = 'attending'))
  ),
  journal as (
    select j.id, coalesce(j.title, 'Eigener Konzertabend') as title, j.starts_at, j.duration_minutes, j.venue_id,
           coalesce(v.name, j.venue_name) as venue_name, j.program, j.participants
      from user_concert_entries j left join venues v on v.id = j.venue_id
     where j.user_id = auth.uid() and j.starts_at >= v_from and j.starts_at < v_to and j.starts_at <= now()
  ),
  composers as (
    select a.id::text as concert, p.full_name as name from attended a
      join event_works ew on ew.event_id = a.id join works wk on wk.id = ew.work_id join persons p on p.id = wk.composer_id
    union
    select j.id::text, coalesce(p.full_name, item->>'composer') from journal j
      cross join lateral jsonb_array_elements(j.program) item
      left join works wk on wk.id = nullif(item->>'work_id', '')::uuid
      left join persons p on p.id = wk.composer_id
     where coalesce(p.full_name, item->>'composer') is not null
  ),
  venue_names as (
    select v.name from attended a join venues v on v.id = a.venue_id
    union all
    select venue_name from journal where venue_name is not null
  ),
  artists as (
    select coalesce(pp.full_name, en.name) as name from attended a join event_participants ep on ep.event_id = a.id
      left join persons pp on pp.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
    union all
    select item->>'name' from journal j cross join lateral jsonb_array_elements(j.participants) item
  )
  select jsonb_build_object(
    'year', v_year,
    'concerts', (select count(*) from attended) + (select count(*) from journal),
    'minutes', (select coalesce(sum(coalesce(duration_minutes, extract(epoch from (end_datetime - start_datetime)) / 60, 120)), 0)::int from attended)
               + (select coalesce(sum(coalesce(duration_minutes, 120)), 0)::int from journal),
    'venues', (select count(distinct name) from venue_names),
    'top_composers', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'count', c)) from (
        select name, count(distinct concert) c from composers group by name order by c desc, name limit 3) t), '[]'),
    'top_venue', (select name from venue_names group by name order by count(*) desc limit 1),
    'top_artist', (select name from artists where name is not null group by name order by count(*) desc limit 1),
    'best_rated', (select jsonb_build_object('title', e.title, 'stars', r.stars, 'slug', e.slug) from event_ratings r join attended e on e.id = r.event_id
                    where r.user_id = auth.uid() order by r.stars desc, e.start_datetime desc limit 1),
    'first', (select jsonb_build_object('title', title, 'date', d) from (
        select title, start_datetime d from attended union all select title, starts_at from journal) f order by d limit 1)
  ) into v_result;
  return v_result;
end; $$;
grant execute on function public.my_concert_year(int) to authenticated;

create or replace function public.user_profile(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_friend boolean := are_friends(auth.uid(), p_user_id);
  v_profile profiles%rowtype;
begin
  select * into v_profile from profiles where id = p_user_id;
  if v_profile.id is null or is_blocked_between(auth.uid(), p_user_id) then return null; end if;
  if not (v_friend or v_profile.is_public or p_user_id = auth.uid()) then
    return jsonb_build_object('user_id', p_user_id, 'display_name', v_profile.display_name, 'avatar_url', v_profile.avatar_url, 'visible', false,
      'status', case when exists (select 1 from friend_requests r where r.from_user = auth.uid() and r.to_user = p_user_id) then 'requested'
                     when exists (select 1 from friend_requests r where r.from_user = p_user_id and r.to_user = auth.uid()) then 'incoming' else 'none' end);
  end if;
  return jsonb_build_object(
    'user_id', p_user_id, 'display_name', v_profile.display_name, 'avatar_url', v_profile.avatar_url, 'bio', v_profile.bio,
    'visible', true, 'is_friend', v_friend,
    'status', case when v_friend then 'friend'
                   when exists (select 1 from friend_requests r where r.from_user = auth.uid() and r.to_user = p_user_id) then 'requested'
                   when exists (select 1 from friend_requests r where r.from_user = p_user_id and r.to_user = auth.uid()) then 'incoming' else 'none' end,
    'concerts', (select count(*) from event_attendance where user_id = p_user_id)
                + (select count(*) from user_concert_entries where user_id = p_user_id and starts_at <= now()),
    'friends', (select count(*) from friendships where user_id = p_user_id),
    'mutual_friends', (select count(*) from friendships a join friendships b on b.friend_id = a.friend_id where a.user_id = auth.uid() and b.user_id = p_user_id),
    'top_composers', coalesce((
      select jsonb_agg(name) from (
        select c.full_name as name from event_attendance a
        join event_works ew on ew.event_id = a.event_id
        join works w on w.id = ew.work_id
        join persons c on c.id = w.composer_id
        where a.user_id = p_user_id
        group by c.full_name order by count(distinct a.event_id) desc limit 5) t), '[]'::jsonb),
    'upcoming', coalesce((
      select jsonb_agg(jsonb_build_object('event_id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime, 'venue_name', v.name) order by e.start_datetime)
      from favorites f join events e on e.id = f.event_id left join venues v on v.id = e.venue_id
      where f.user_id = p_user_id and f.status = 'attending' and e.start_datetime >= now() and (v_friend or p_user_id = auth.uid())), '[]'::jsonb)
  );
end; $$;

notify pgrst, 'reload schema';
