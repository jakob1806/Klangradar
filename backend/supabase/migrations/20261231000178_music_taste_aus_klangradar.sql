-- Erstellt von Claude Code (18.11.2026): Musikgeschmack lernt aus Klangradar
-- selbst – Gefolgte, Lieblingswerke, gemerkte, geplante und besuchte
-- Konzerte (Tagebuch). Läuft auch ganz ohne Last.fm/Apple Music. Frühere
-- Klangradar-Signale werden ersetzt, Daten anderer Quellen bleiben erhalten.
create or replace function public.music_taste_from_app(p_city_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_app jsonb;
  v_keep jsonb;
  v_tracks jsonb;
begin
  if v_uid is null then raise exception 'Nicht angemeldet.'; end if;
  with signals as (
    select p.full_name as name, 4.0 as w from user_favorite_persons f join persons p on p.id = f.person_id where f.user_id = v_uid
    union all
    select e.name, 4.0 from user_favorite_ensembles f join ensembles e on e.id = f.ensemble_id where f.user_id = v_uid
    union all
    select p.full_name, 3.0 from user_favorite_works f join works w on w.id = f.work_id join persons p on p.id = w.composer_id where f.user_id = v_uid
    union all
    -- Konzerte: gemerkt (1), geplant/besucht (2), im Tagebuch (3)
    select coalesce(p.full_name, en.name), x.w
    from (
      select event_id, 1.0 as w from favorites where user_id = v_uid
      union all select event_id, 2.0 from event_attendance where user_id = v_uid
      union all select event_id, 3.0 from concert_diary_entries where user_id = v_uid
    ) x
    join event_participants ep on ep.event_id = x.event_id
    left join persons p on p.id = ep.person_id
    left join ensembles en on en.id = ep.ensemble_id
    union all
    select p.full_name, x.w * 1.5
    from (
      select event_id, 1.0 as w from favorites where user_id = v_uid
      union all select event_id, 2.0 from event_attendance where user_id = v_uid
      union all select event_id, 3.0 from concert_diary_entries where user_id = v_uid
    ) x
    join event_works ew on ew.event_id = x.event_id
    join works w on w.id = ew.work_id
    join persons p on p.id = w.composer_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'weight', round(log(2, (w + 1)::numeric), 2), 'genres', '[]'::jsonb, 'source', 'klangradar')), '[]')
    into v_app
  from (select name, sum(w) w from signals where name is not null group by name order by sum(w) desc limit 120) s;
  v_app := coalesce(v_app, '[]');

  select coalesce((select jsonb_agg(a) from jsonb_array_elements(coalesce(m.artists, '[]')) a where coalesce(a->>'source', '') <> 'klangradar'), '[]'),
         coalesce(m.tracks, '[]')
    into v_keep, v_tracks
  from (select 1) d left join music_taste_profiles m on m.user_id = v_uid;

  if jsonb_array_length(v_app) = 0 and jsonb_array_length(coalesce(v_keep, '[]')) = 0 then
    return music_taste_recommendations(p_city_id);
  end if;
  return music_taste_analyze(coalesce(v_keep, '[]') || v_app, coalesce(v_tracks, '[]'), array['klangradar'], p_city_id, null, false);
end; $$;
grant execute on function public.music_taste_from_app(uuid) to authenticated;
