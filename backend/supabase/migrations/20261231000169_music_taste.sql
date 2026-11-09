-- Musikgeschmack aus Spotify / Apple Music (09.11.2026).
-- Die App liest auf dem Gerät die meistgehörten Künstler:innen und Titel
-- (nie Zugangsdaten) und übergibt sie hier. Der Abgleich ordnet sie
-- Personen, Ensembles und Werken zu; daraus entstehen Empfehlungen.
create table if not exists public.music_taste_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  providers text[] not null default '{}',
  artists jsonb not null default '[]',
  tracks jsonb not null default '[]',
  matches jsonb not null default '{}',
  updated_at timestamptz not null default now()
);
alter table public.music_taste_profiles enable row level security;
drop policy if exists "Eigenes Musikprofil" on public.music_taste_profiles;
create policy "Eigenes Musikprofil" on public.music_taste_profiles for select using (user_id = auth.uid());

-- p_artists: [{name, weight, genres:[...]}], p_tracks: [{title, artist, composer, weight}]
create or replace function public.music_taste_analyze(p_artists jsonb, p_tracks jsonb, p_providers text[])
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_matches jsonb;
begin
  if v_uid is null then raise exception 'Nicht angemeldet.'; end if;
  with names as (
    select search_norm(a->>'name') as n, coalesce((a->>'weight')::numeric, 1) as w
    from jsonb_array_elements(coalesce(p_artists, '[]')) a where coalesce(a->>'name', '') <> ''
    union all
    select search_norm(coalesce(t->>'composer', '')), coalesce((t->>'weight')::numeric, 1) * 1.5
    from jsonb_array_elements(coalesce(p_tracks, '[]')) t where coalesce(t->>'composer', '') <> ''
    union all
    select search_norm(t->>'artist'), coalesce((t->>'weight')::numeric, 1) * 0.5
    from jsonb_array_elements(coalesce(p_tracks, '[]')) t where coalesce(t->>'artist', '') <> ''
  ), agg as (select n, sum(w) w from names where length(n) >= 4 group by n),
  person_hits as (
    select p.id, p.slug, p.full_name as title, p.photo_url, sum(a.w) as score,
           ('composer' = any(p.roles::text[])) as is_composer
    from agg a join persons p on search_norm(p.full_name) = a.n
    group by p.id
  ),
  ensemble_hits as (
    select e.id, e.slug, e.name as title, e.photo_url, sum(a.w) as score
    from agg a join ensembles e on search_norm(e.name) = a.n
    group by e.id
  ),
  work_hits as (
    select w.id, w.title, ph.title as composer, sum(coalesce((t->>'weight')::numeric, 1)) as score
    from jsonb_array_elements(coalesce(p_tracks, '[]')) t
    join person_hits ph on ph.title is not null
      and search_norm(coalesce(t->>'composer', t->>'artist', '')) = search_norm(ph.title)
    join works w on w.composer_id = ph.id
      and similarity(search_norm(w.title), search_norm(t->>'title')) > 0.35
    group by w.id, w.title, ph.title
  ),
  genre_counts as (
    select g, count(*) c from jsonb_array_elements(coalesce(p_artists, '[]')) a,
      jsonb_array_elements_text(coalesce(a->'genres', '[]')) g group by g order by c desc limit 8
  )
  select jsonb_build_object(
    'persons', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc) from (select * from person_hits order by score desc limit 40) x), '[]'),
    'ensembles', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc) from (select * from ensemble_hits order by score desc limit 20) x), '[]'),
    'works', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc) from (select * from work_hits order by score desc limit 30) x), '[]'),
    'genres', coalesce((select jsonb_agg(g order by c desc) from genre_counts), '[]'),
    'artist_count', jsonb_array_length(coalesce(p_artists, '[]')),
    'track_count', jsonb_array_length(coalesce(p_tracks, '[]'))
  ) into v_matches;

  insert into music_taste_profiles (user_id, providers, artists, tracks, matches, updated_at)
  values (v_uid, coalesce(p_providers, '{}'), coalesce(p_artists, '[]'), coalesce(p_tracks, '[]'), v_matches, now())
  on conflict (user_id) do update set
    providers = (select array(select distinct unnest(music_taste_profiles.providers || excluded.providers))),
    artists = excluded.artists, tracks = excluded.tracks, matches = excluded.matches, updated_at = now();
  return music_taste_recommendations();
end; $$;
grant execute on function public.music_taste_analyze(jsonb, jsonb, text[]) to authenticated;

-- Empfehlungen aus den Treffern: kommende Konzerte mit diesen Personen,
-- Ensembles oder Werken, Spielstätten dieser Konzerte, dazu die Treffer.
create or replace function public.music_taste_recommendations()
returns jsonb language sql stable security definer set search_path = public as $$
  with prof as (select * from music_taste_profiles where user_id = auth.uid()),
  pids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'persons') x),
  eids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'ensembles') x),
  wids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'works') x),
  ev as (
    select e.id, e.slug, e.title, e.start_datetime, e.image_urls[1] as image_url, v.name as venue, v.id as venue_id,
           sum(s.s) as score, (array_agg(distinct s.reason))[1:3] as reasons
    from events e
    left join venues v on v.id = e.venue_id
    join (
      select ep.event_id, p.s, pe.full_name as reason from event_participants ep join pids p on p.id = ep.person_id join persons pe on pe.id = p.id
      union all
      select ep.event_id, x.s, en.name from event_participants ep join eids x on x.id = ep.ensemble_id join ensembles en on en.id = x.id
      union all
      select ew.event_id, x.s * 1.5, wo.title from event_works ew join wids x on x.id = ew.work_id join works wo on wo.id = x.id
      union all
      select ew.event_id, p.s, pe.full_name from event_works ew join works wo on wo.id = ew.work_id join pids p on p.id = wo.composer_id join persons pe on pe.id = p.id
    ) s on s.event_id = e.id
    where e.start_datetime > now() and e.status <> 'draft' and e.status <> 'cancelled'
    group by e.id, v.name, v.id
    order by sum(s.s) desc, e.start_datetime
    limit 40
  )
  select case when not exists (select 1 from prof) then null else jsonb_build_object(
    'providers', (select to_jsonb(providers) from prof),
    'updated_at', (select updated_at from prof),
    'genres', (select matches->'genres' from prof),
    'artist_count', (select matches->'artist_count' from prof),
    'track_count', (select matches->'track_count' from prof),
    'persons', (select matches->'persons' from prof),
    'ensembles', (select matches->'ensembles' from prof),
    'works', (select matches->'works' from prof),
    'events', coalesce((select jsonb_agg(to_jsonb(ev) order by ev.score desc, ev.start_datetime) from ev), '[]'),
    'venues', coalesce((select jsonb_agg(to_jsonb(x)) from (
       select ev.venue_id as id, ev.venue as title, count(*) as event_count from ev where ev.venue_id is not null
       group by ev.venue_id, ev.venue order by count(*) desc limit 10) x), '[]')
  ) end;
$$;
grant execute on function public.music_taste_recommendations() to authenticated;

create or replace function public.music_taste_disconnect()
returns void language sql security definer set search_path = public as $$
  delete from music_taste_profiles where user_id = auth.uid();
$$;
grant execute on function public.music_taste_disconnect() to authenticated;
