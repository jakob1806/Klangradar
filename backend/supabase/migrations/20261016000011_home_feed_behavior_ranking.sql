-- Personalisiertes Home-Feed-Ranking V2: Explizite Interessen bleiben das
-- stärkste Signal; wiederholte, aktuelle Handlungen liefern abgestufte statt
-- bloß boolesche Evidenz. Impression-Fatigue ersetzt den harten 7-Tage-
-- Ausschluss, damit kleine Kataloge nicht leer gerankt werden.

insert into home_feed_ranking_weights (key, weight, description) values
  ('favorite_behavior', 1.8, 'Affinity aus Favoriten ähnlicher Events'),
  ('view_behavior', 1.2, 'Zeitlich gewichtete Detailansichten; lange Views zählen stärker'),
  ('ticket_behavior', 2.2, 'Zeitlich gewichtete Ticketklicks ähnlicher Events'),
  ('impression_fatigue', 1.5, 'Malus pro kürzlich erfolgter Für-dich-Impression')
on conflict (key) do update
set weight = excluded.weight, description = excluded.description;

drop function if exists recommended_events(int);

create function recommended_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[],
  rank_score numeric, rank_reason text[]
)
language sql
stable
as $$
with weights as (
  select
    max(weight) filter (where key = 'genre_interest') as genre,
    max(weight) filter (where key = 'work_interest') as work,
    max(weight) filter (where key = 'venue_interest') as venue,
    max(weight) filter (where key = 'person_interest') as person,
    max(weight) filter (where key = 'ensemble_interest') as ensemble,
    max(weight) filter (where key = 'popularity_scale') as popularity,
    max(weight) filter (where key = 'time_decay_divisor_days') as time_days,
    max(weight) filter (where key = 'favorite_behavior') as favorite_behavior,
    max(weight) filter (where key = 'view_behavior') as view_behavior,
    max(weight) filter (where key = 'ticket_behavior') as ticket_behavior,
    max(weight) filter (where key = 'impression_fatigue') as fatigue
  from home_feed_ranking_weights
), candidates as (
  select
    e.*, v.name as venue_name,
    exists (
      select 1 from event_genres eg join profile_interest_genres pig using (genre_id)
      where eg.event_id = e.id and pig.user_id = auth.uid()
    ) as genre_match,
    exists (
      select 1 from event_works ew join user_favorite_works ufw using (work_id)
      where ew.event_id = e.id and ufw.user_id = auth.uid()
    ) as work_match,
    exists (
      select 1 from user_favorite_venues ufv
      where ufv.user_id = auth.uid() and ufv.venue_id = e.venue_id
    ) as venue_match,
    exists (
      select 1 from event_participants ep join user_favorite_persons ufp using (person_id)
      where ep.event_id = e.id and ufp.user_id = auth.uid()
    ) as person_match,
    exists (
      select 1 from event_participants ep join user_favorite_ensembles ufe using (ensemble_id)
      where ep.event_id = e.id and ufe.user_id = auth.uid()
    ) as ensemble_match,
    -- Ähnlich bedeutet: gleicher Ort, Genre, Person oder Ensemble. Pro
    -- Ereignistyp wird gedeckelt, damit Power-User das Ranking nicht sprengen.
    least(3, (select count(*) from favorites f join events fe on fe.id = f.event_id
      where f.user_id = auth.uid() and (
        fe.venue_id = e.venue_id or exists (
          select 1 from event_genres a join event_genres b using (genre_id)
          where a.event_id = e.id and b.event_id = fe.id
        )
      )))::numeric as favorite_signal,
    least(3, coalesce((select sum(
      exp(-extract(epoch from (now() - ev.viewed_at)) / 2592000.0)
      * case when coalesce(ev.duration_seconds, 0) >= 30 then 1.0
             when coalesce(ev.duration_seconds, 0) >= 10 then 0.6 else 0.2 end)
      from event_views ev join events ve on ve.id = ev.event_id
      where ev.user_id = auth.uid() and ev.viewed_at >= now() - interval '90 days'
        and (ve.venue_id = e.venue_id or exists (
          select 1 from event_genres a join event_genres b using (genre_id)
          where a.event_id = e.id and b.event_id = ve.id
        ))), 0))::numeric as view_signal,
    least(3, coalesce((select sum(exp(-extract(epoch from (now() - tc.clicked_at)) / 5184000.0))
      from ticket_clicks tc join events te on te.id = tc.event_id
      where tc.user_id = auth.uid() and tc.clicked_at >= now() - interval '180 days'
        and (te.venue_id = e.venue_id or exists (
          select 1 from event_genres a join event_genres b using (genre_id)
          where a.event_id = e.id and b.event_id = te.id
        ))), 0))::numeric as ticket_signal,
    (select ln(1 + count(*)::numeric) from favorites f where f.event_id = e.id) as popularity_signal,
    (select count(*) from home_feed_impressions h
      where h.user_id = auth.uid() and h.event_id = e.id
        and h.module_key = 'fuer_dich' and h.shown_at >= now() - interval '14 days')::numeric as impression_count
  from events e join venues v on v.id = e.venue_id
  where e.status = 'scheduled' and e.start_datetime >= now()
), scored as (
  select c.*, (
    case when genre_match then coalesce(w.genre, 5) else 0 end
    + case when work_match then coalesce(w.work, 5) else 0 end
    + case when venue_match then coalesce(w.venue, 3) else 0 end
    + case when person_match then coalesce(w.person, 4) else 0 end
    + case when ensemble_match then coalesce(w.ensemble, 4) else 0 end
    + favorite_signal * coalesce(w.favorite_behavior, 1.8)
    + view_signal * coalesce(w.view_behavior, 1.2)
    + ticket_signal * coalesce(w.ticket_behavior, 2.2)
    + popularity_signal * coalesce(w.popularity, .5)
    - impression_count * coalesce(w.fatigue, 1.5)
    - extract(epoch from (c.start_datetime - now())) / 86400.0 / coalesce(w.time_days, 30)
  ) as score
  from candidates c cross join weights w
)
select
  s.id, s.slug, s.title, s.subtitle, s.is_free,
  s.remaining_tickets_status, s.start_datetime, s.venue_id,
  jsonb_build_object('name', s.venue_name),
  coalesce((select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
    from event_genres eg join genres g on g.id = eg.genre_id where eg.event_id = s.id), '[]'::jsonb),
  s.image_urls, round(s.score, 3),
  array_remove(array[
    case when genre_match then 'genre_interesse' end,
    case when work_match then 'werk_interesse' end,
    case when venue_match then 'venue_gefolgt' end,
    case when person_match then 'person_gefolgt' end,
    case when ensemble_match then 'ensemble_gefolgt' end,
    case when favorite_signal > 0 then 'aehnliche_favoriten' end,
    case when view_signal > 0 then 'ansichtsverhalten' end,
    case when ticket_signal > 0 then 'ticketinteresse' end,
    case when impression_count > 0 then 'wiederholungsmalus' end
  ], null)
from scored s
order by s.score desc, s.start_datetime
limit greatest(1, least(p_result_limit, 50));
$$;

grant execute on function recommended_events(int) to anon, authenticated;
