-- Erstellt von Claude Code (13.11.2026): Musikgeschmack v2.
-- • Komponisten auch aus dem Titel („Bruckner: Sinfonie Nr. 7“)
-- • ungefähre Namenssuche (Nachname bei Komponist:innen, Ähnlichkeit)
-- • „Das hörst du“: meistgehörte Künstler:innen/Titel mit Treffer-Info
-- • Empfehlungen nur für die gewählte Stadt, Gewichtung nach Anzahl der
--   Gründe und Nähe des Termins, Genre-Rückfall, Hinweis auf andere Städte

drop function if exists public.music_taste_analyze(jsonb, jsonb, text[]);
drop function if exists public.music_taste_recommendations();

create or replace function public.music_taste_analyze(
  p_artists jsonb, p_tracks jsonb, p_providers text[], p_city_id uuid default null, p_period text default null,
  p_merge boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_matches jsonb;
begin
  if v_uid is null then raise exception 'Nicht angemeldet.'; end if;
  -- p_merge (Shazam): neue Treffer zu den gespeicherten hinzufügen statt ersetzen.
  if p_merge then
    select coalesce(m.artists, '[]') || coalesce(p_artists, '[]'), coalesce(m.tracks, '[]') || coalesce(p_tracks, '[]')
      into p_artists, p_tracks
    from (select 1) d left join music_taste_profiles m on m.user_id = v_uid;
  end if;
  with tracks as (
    select t, coalesce((t->>'weight')::numeric, 1) w,
      -- „Bruckner: Symphony No. 7“ → Bruckner
      nullif(trim(substring(t->>'title' from '^([^:]{3,40}):')), '') as title_composer
    from jsonb_array_elements(coalesce(p_tracks, '[]')) t
  ),
  names as (
    select search_norm(a->>'name') as n, coalesce((a->>'weight')::numeric, 1) as w, a->>'name' as raw
    from jsonb_array_elements(coalesce(p_artists, '[]')) a where coalesce(a->>'name', '') <> ''
    union all
    select search_norm(t->>'composer'), w * 1.5, t->>'composer' from tracks where coalesce(t->>'composer', '') <> ''
    union all
    select search_norm(title_composer), w * 1.5, title_composer from tracks where title_composer is not null
    union all
    select search_norm(t->>'artist'), w * 0.5, t->>'artist' from tracks where coalesce(t->>'artist', '') <> ''
  ),
  agg as (select n, sum(w) w from names where length(n) >= 4 group by n),
  pnorm as materialized (
    select p.id, p.slug, p.full_name, p.photo_url, ('composer' = any(p.roles::text[])) as is_composer,
           search_norm(p.full_name) as n, regexp_replace(search_norm(p.full_name), '^.* ', '') as last
    from persons p
  ),
  person_match as (
    select distinct on (a.n) a.n, a.w, p.id
    from agg a join pnorm p on p.n = a.n
      or (p.is_composer and length(a.n) >= 5 and position(' ' in a.n) = 0 and p.last = a.n)
      or (length(a.n) >= 10 and similarity(p.n, a.n) > 0.72)
    order by a.n, (p.n = a.n) desc, p.is_composer desc, similarity(p.n, a.n) desc
  ),
  person_hits as (
    select p.id, p.slug, p.full_name as title, p.photo_url, sum(m.w) as score, p.is_composer
    from person_match m join pnorm p on p.id = m.id group by p.id, p.slug, p.full_name, p.photo_url, p.is_composer
  ),
  ensemble_match as (
    select distinct on (a.n) a.n, a.w, e.id
    from agg a join ensembles e on search_norm(e.name) = a.n
      or (length(a.n) >= 10 and similarity(search_norm(e.name), a.n) > 0.75)
    order by a.n, (search_norm(e.name) = a.n) desc
  ),
  ensemble_hits as (
    select e.id, e.slug, e.name as title, e.photo_url, sum(m.w) as score
    from ensemble_match m join ensembles e on e.id = m.id group by e.id
  ),
  work_hits as (
    select w.id, w.title, ph.title as composer, sum(t.w) as score
    from tracks t
    join person_hits ph on ph.is_composer and (
      search_norm(coalesce(t.title_composer, t.t->>'composer', t.t->>'artist', '')) = search_norm(ph.title)
      or regexp_replace(search_norm(ph.title), '^.* ', '') = search_norm(coalesce(t.title_composer, t.t->>'composer', '')))
    join works w on w.composer_id = ph.id
      and similarity(search_norm(w.title), search_norm(regexp_replace(t.t->>'title', '^[^:]{3,40}:\s*', ''))) > 0.35
    group by w.id, w.title, ph.title
  ),
  genre_counts as (
    select lower(g) g, count(*) c from jsonb_array_elements(coalesce(p_artists, '[]')) a,
      jsonb_array_elements_text(coalesce(a->'genres', '[]')) g group by lower(g) order by c desc limit 8
  ),
  listened as (
    select a->>'name' as name, coalesce((a->>'weight')::numeric, 1) as weight,
      row_number() over (order by coalesce((a->>'weight')::numeric, 1) desc) as rank,
      pm.id as person_id, em.id as ensemble_id
    from jsonb_array_elements(coalesce(p_artists, '[]')) a
    left join person_match pm on pm.n = search_norm(a->>'name')
    left join ensemble_match em on em.n = search_norm(a->>'name')
    where coalesce(a->>'name', '') <> ''
  )
  select jsonb_build_object(
    'persons', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc) from (select * from person_hits order by score desc limit 40) x), '[]'),
    'ensembles', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc) from (select * from ensemble_hits order by score desc limit 20) x), '[]'),
    'works', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc) from (select * from work_hits order by score desc limit 30) x), '[]'),
    'genres', coalesce((select jsonb_agg(g order by c desc) from genre_counts), '[]'),
    'listened', coalesce((select jsonb_agg(to_jsonb(l) order by l.rank) from (select * from listened order by rank limit 40) l), '[]'),
    'top_tracks', coalesce((select jsonb_agg(jsonb_build_object('title', t->>'title', 'artist', t->>'artist') order by w desc)
                            from (select t, w from tracks order by w desc limit 15) x), '[]'),
    'artist_count', jsonb_array_length(coalesce(p_artists, '[]')),
    'track_count', jsonb_array_length(coalesce(p_tracks, '[]')),
    'period', coalesce(p_period, (select matches->>'period' from music_taste_profiles where user_id = v_uid))
  ) into v_matches;

  insert into music_taste_profiles (user_id, providers, artists, tracks, matches, updated_at)
  values (v_uid, coalesce(p_providers, '{}'), coalesce(p_artists, '[]'), coalesce(p_tracks, '[]'), v_matches, now())
  on conflict (user_id) do update set
    providers = (select array(select distinct unnest(music_taste_profiles.providers || excluded.providers))),
    artists = excluded.artists, tracks = excluded.tracks, matches = excluded.matches, updated_at = now();
  return music_taste_recommendations(p_city_id);
end; $$;
grant execute on function public.music_taste_analyze(jsonb, jsonb, text[], uuid, text, boolean) to authenticated;

-- Genre-Schlagworte (Last.fm/Apple Music) → Klangradar-Genres.
create or replace function public.music_taste_genre_slugs(p_genres jsonb)
returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct s), '{}') from (
    select case
      when g ~ 'opera|oper' then 'oper'
      when g ~ 'choral|choir|chor' then 'chormusik'
      when g ~ 'sacred|gospel|church|kirche|requiem' then 'kirchenmusik'
      when g ~ 'chamber|kammer|piano|string quartet|klavier' then 'kammermusik'
      when g ~ 'lied|art song' then 'liederabend'
      when g ~ 'organ|orgel' then 'orgel'
      when g ~ 'jazz|swing|bebop' then 'jazz'
      when g ~ 'contemporary|avant|minimal|neue musik|modern classical|ambient|electronic' then 'neue_musik'
      when g ~ 'classical|klassik|orchest|symphon|baroque|barock|romantic|soundtrack|film|score|crossover' then 'orchester'
    end as s
    from jsonb_array_elements_text(coalesce(p_genres, '[]')) x(g0), lateral (select lower(g0) as g) l
  ) y where s is not null;
$$;

create or replace function public.music_taste_recommendations(p_city_id uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with prof as (select * from music_taste_profiles where user_id = auth.uid()),
  pids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'persons') x),
  eids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'ensembles') x),
  wids as (select (x->>'id')::uuid id, (x->>'score')::numeric s from prof, jsonb_array_elements(prof.matches->'works') x),
  upcoming as (
    select e.id, e.slug, e.title, e.start_datetime, e.image_urls[1] as image_url, v.name as venue, v.id as venue_id,
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
    group by u.id, u.slug, u.title, u.start_datetime, u.image_url, u.venue, u.venue_id, u.city_id
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
    'listened', coalesce((select jsonb_agg(l || jsonb_build_object('upcoming',
        coalesce((select sum(n) from person_up where id = (l->>'person_id')::uuid), 0)
        + coalesce((select sum(n) from ensemble_up where id = (l->>'ensemble_id')::uuid), 0)))
      from prof, jsonb_array_elements(coalesce(prof.matches->'listened', '[]')) l), '[]'),
    'persons', coalesce((select jsonb_agg(x || jsonb_build_object('upcoming', coalesce((select sum(n) from person_up where id = (x->>'id')::uuid), 0)))
      from prof, jsonb_array_elements(prof.matches->'persons') x), '[]'),
    'ensembles', coalesce((select jsonb_agg(x || jsonb_build_object('upcoming', coalesce((select sum(n) from ensemble_up where id = (x->>'id')::uuid), 0)))
      from prof, jsonb_array_elements(prof.matches->'ensembles') x), '[]'),
    'works', (select matches->'works' from prof),
    'events', coalesce((select jsonb_agg(to_jsonb(ev) order by ev.score desc, ev.start_datetime) from ev), '[]'),
    'venues', coalesce((select jsonb_agg(to_jsonb(x)) from (
       select ev.venue_id as id, ev.venue as title, count(*) as event_count from ev where ev.venue_id is not null
       group by ev.venue_id, ev.venue order by count(*) desc limit 10) x), '[]'),
    'other_city_count', (select n from other_city),
    'other_city', (select city from other_city)
  ) end;
$$;
grant execute on function public.music_taste_recommendations(uuid) to authenticated;
