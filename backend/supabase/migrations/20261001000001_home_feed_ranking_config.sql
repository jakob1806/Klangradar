-- Home-Feed Phase A, Rest (siehe docs/08-home-feed-recommendation-algorithm.md,
-- Abschnitt 2/3): Modul-Reihenfolge + Diversitätsregeln 1-3 sind bereits seit
-- PR #114 in home_providers.dart live (_orderedModules/_applyDiversity). Was
-- laut Plan noch fehlte: eine zentrale Gewichtungs-Konfiguration statt
-- Zahlen-Literalen mitten in der SQL-Query, und ein rank_reason/rank_score
-- pro Zeile, damit eine Platzierung intern nachvollziehbar ist (nicht nur
-- "irgendein Score", sondern welche Signale konkret gegriffen haben).

-- Eine echte Tabelle statt einer JSONB-Konstante im Funktionskörper, damit
-- Gewichte ohne Redeploy der Function angepasst werden können (einmaliger
-- Lookup pro Funktionsaufruf, kein N+1 — nicht pro Zeile).
create table if not exists home_feed_ranking_weights (
  key text primary key,
  weight numeric not null,
  description text not null
);

insert into home_feed_ranking_weights (key, weight, description) values
  ('genre_interest', 5, 'Bonus wenn ein Event zu einem von der Person favorisierten Genre gehört'),
  ('venue_interest', 3, 'Bonus wenn die Venue favorisiert ist oder die Person dort schon ein Event angesehen hat'),
  ('person_interest', 4, 'Bonus wenn ein mitwirkender Komponist/Interpret favorisiert ist'),
  ('ensemble_interest', 4, 'Bonus wenn ein mitwirkendes Ensemble favorisiert ist'),
  ('popularity_scale', 0.5, 'Multiplikator auf ln(1 + Anzahl Favorisierungen) — log-skaliert, siehe 20260903000001'),
  ('time_decay_divisor_days', 30, 'Je größer, desto schwächer wertet zeitliche Distanz zukünftige Events ab')
on conflict (key) do nothing;

alter table home_feed_ranking_weights enable row level security;

create policy "home_feed_ranking_weights_read_all"
  on home_feed_ranking_weights for select
  using (true);

drop function if exists recommended_events(int);

create function recommended_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[],
  rank_score numeric, rank_reason text[]
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  w_genre numeric;
  w_venue numeric;
  w_person numeric;
  w_ensemble numeric;
  w_popularity numeric;
  w_time_decay_days numeric;
begin
  select weight into w_genre from home_feed_ranking_weights where key = 'genre_interest';
  select weight into w_venue from home_feed_ranking_weights where key = 'venue_interest';
  select weight into w_person from home_feed_ranking_weights where key = 'person_interest';
  select weight into w_ensemble from home_feed_ranking_weights where key = 'ensemble_interest';
  select weight into w_popularity from home_feed_ranking_weights where key = 'popularity_scale';
  select weight into w_time_decay_days from home_feed_ranking_weights where key = 'time_decay_divisor_days';

  return query
    with scored as (
      select
        e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status, e.start_datetime,
        v.id as venue_id,
        jsonb_build_object('name', v.name) as venues,
        coalesce(
          (
            select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
            from event_genres eg
            join genres g on g.id = eg.genre_id
            where eg.event_id = e.id
          ),
          '[]'::jsonb
        ) as event_genres,
        e.image_urls,
        (v_uid is not null and exists (
          select 1 from event_genres eg
          join profile_interest_genres pig on pig.genre_id = eg.genre_id
          where eg.event_id = e.id and pig.user_id = v_uid
        )) as has_genre_match,
        (v_uid is not null and (
          exists (
            select 1 from user_favorite_venues ufv
            where ufv.venue_id = e.venue_id and ufv.user_id = v_uid
          )
          or exists (
            select 1 from event_views ev
            join events e2 on e2.id = ev.event_id
            where e2.venue_id = e.venue_id and ev.user_id = v_uid
          )
        )) as has_venue_match,
        (v_uid is not null and exists (
          select 1 from event_participants ep
          join user_favorite_persons ufp on ufp.person_id = ep.person_id
          where ep.event_id = e.id and ufp.user_id = v_uid
        )) as has_person_match,
        (v_uid is not null and exists (
          select 1 from event_participants ep
          join user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
          where ep.event_id = e.id and ufe.user_id = v_uid
        )) as has_ensemble_match,
        (select ln(1 + count(*)::float) from favorites f where f.event_id = e.id) as popularity_raw
      from events e
      join venues v on v.id = e.venue_id
      where e.status = 'scheduled' and e.start_datetime >= now()
    )
    select
      s.id, s.slug, s.title, s.subtitle, s.is_free, s.remaining_tickets_status, s.start_datetime,
      s.venue_id, s.venues, s.event_genres, s.image_urls,
      round((
        (case when has_genre_match then w_genre else 0 end)
        + (case when has_venue_match then w_venue else 0 end)
        + (case when has_person_match then w_person else 0 end)
        + (case when has_ensemble_match then w_ensemble else 0 end)
        + coalesce(popularity_raw, 0) * w_popularity
        - (extract(epoch from (s.start_datetime - now())) / 86400.0 / w_time_decay_days)
      )::numeric, 3) as rank_score,
      array_remove(array[
        case when has_genre_match then 'genre_interesse' end,
        case when has_venue_match then 'venue_interesse' end,
        case when has_person_match then 'mitwirkende_interesse' end,
        case when has_ensemble_match then 'ensemble_interesse' end,
        case when coalesce(popularity_raw, 0) > 0 then 'popularitaet' end
      ], null) as rank_reason
    from scored s
    order by rank_score desc, s.start_datetime
    limit p_result_limit;
end;
$$;

grant execute on function recommended_events(int) to anon, authenticated;
