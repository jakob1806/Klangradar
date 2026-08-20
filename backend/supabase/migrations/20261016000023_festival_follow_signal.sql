-- Empfehlungssystem-Anfrage (Punkt 25, "Folgen als Kernfeature" —
-- Recommendation Signal): Festival-Follows (user_favorite_festivals,
-- 20261016000022) sollen wie Venue-/Personen-/Ensemble-Follows in
-- recommended_events() einfließen, nicht nur die Push-Benachrichtigung
-- speisen.
insert into home_feed_ranking_weights (key, weight, description) values
  ('festival_interest', 4, 'Bonus wenn das Event zu einem gefolgten Festival gehört')
on conflict (key) do update set weight = excluded.weight, description = excluded.description;

-- recommended_events() erneut neu definiert: + Festival-Signal, sonst
-- unverändert gegenüber 20261016000021 (Kalender-Signal).
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
    max(weight) filter (where key = 'festival_interest') as festival,
    max(weight) filter (where key = 'popularity_scale') as popularity,
    max(weight) filter (where key = 'time_decay_divisor_days') as time_days,
    max(weight) filter (where key = 'favorite_behavior') as favorite_behavior,
    max(weight) filter (where key = 'view_behavior') as view_behavior,
    max(weight) filter (where key = 'ticket_behavior') as ticket_behavior,
    max(weight) filter (where key = 'share_behavior') as share_behavior,
    max(weight) filter (where key = 'calendar_behavior') as calendar_behavior,
    max(weight) filter (where key = 'impression_fatigue') as fatigue,
    max(weight) filter (where key = 'availability_penalty') as availability_penalty,
    max(weight) filter (where key = 'box_office_penalty') as box_office_penalty,
    max(weight) filter (where key = 'price_affinity') as price_affinity
  from home_feed_ranking_weights
), dismissed_events as (
  select entity_id from content_dismissals
  where user_id = auth.uid() and entity_type = 'event'
), dismissed_venues as (
  select entity_id from content_dismissals
  where user_id = auth.uid() and entity_type = 'venue'
), dismissed_participants as (
  select entity_id from content_dismissals
  where user_id = auth.uid() and entity_type in ('person', 'ensemble')
), my_price_range as (
  select
    case when count(*) >= 2 then avg(e.price_min) end as avg_price,
    case when count(*) >= 2 then stddev(e.price_min) end as stddev_price
  from ticket_clicks tc
  join events e on e.id = tc.event_id
  where tc.user_id = auth.uid() and tc.clicked_at >= now() - interval '180 days'
    and e.price_min is not null
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
    exists (
      select 1 from user_favorite_festivals uff
      where uff.user_id = auth.uid() and uff.festival_id = e.festival_id
    ) as festival_match,
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
    least(3, coalesce((select sum(exp(-extract(epoch from (now() - es.shared_at)) / 5184000.0))
      from event_shares es join events se on se.id = es.event_id
      where es.user_id = auth.uid() and es.shared_at >= now() - interval '180 days'
        and (se.venue_id = e.venue_id or exists (
          select 1 from event_genres a join event_genres b using (genre_id)
          where a.event_id = e.id and b.event_id = se.id
        ))), 0))::numeric as share_signal,
    least(3, coalesce((select sum(exp(-extract(epoch from (now() - ca.added_at)) / 5184000.0))
      from calendar_adds ca join events cae on cae.id = ca.event_id
      where ca.user_id = auth.uid() and ca.added_at >= now() - interval '180 days'
        and (cae.venue_id = e.venue_id or exists (
          select 1 from event_genres a join event_genres b using (genre_id)
          where a.event_id = e.id and b.event_id = cae.id
        ))), 0))::numeric as calendar_signal,
    (select ln(1 + count(*)::numeric) from favorites f where f.event_id = e.id) as popularity_signal,
    (select count(*) from home_feed_impressions h
      where h.user_id = auth.uid() and h.event_id = e.id
        and h.module_key = 'fuer_dich' and h.shown_at >= now() - interval '14 days')::numeric as impression_count,
    (
      (select avg_price from my_price_range) is not null and e.price_min is not null
      and abs(e.price_min - (select avg_price from my_price_range))
        <= coalesce((select stddev_price from my_price_range), 15)
    ) as price_affinity_match
  from events e join venues v on v.id = e.venue_id
  where e.status = 'scheduled' and e.start_datetime >= now()
    and (auth.uid() is null or e.id not in (select entity_id from dismissed_events))
    and (auth.uid() is null or e.venue_id not in (select entity_id from dismissed_venues))
    and (auth.uid() is null or not exists (
      select 1 from event_participants ep
      where ep.event_id = e.id
        and (ep.person_id in (select entity_id from dismissed_participants)
          or ep.ensemble_id in (select entity_id from dismissed_participants))
    ))
), scored as (
  select c.*, (
    case when genre_match then coalesce(w.genre, 5) else 0 end
    + case when work_match then coalesce(w.work, 5) else 0 end
    + case when venue_match then coalesce(w.venue, 3) else 0 end
    + case when person_match then coalesce(w.person, 4) else 0 end
    + case when ensemble_match then coalesce(w.ensemble, 4) else 0 end
    + case when festival_match then coalesce(w.festival, 4) else 0 end
    + favorite_signal * coalesce(w.favorite_behavior, 1.8)
    + view_signal * coalesce(w.view_behavior, 1.2)
    + ticket_signal * coalesce(w.ticket_behavior, 2.2)
    + share_signal * coalesce(w.share_behavior, 2.0)
    + calendar_signal * coalesce(w.calendar_behavior, 2.5)
    + popularity_signal * coalesce(w.popularity, .5)
    - impression_count * coalesce(w.fatigue, 1.5)
    - case when c.remaining_tickets_status = 'sold_out' then coalesce(w.availability_penalty, 6) else 0 end
    - case when c.remaining_tickets_status = 'box_office_only' then coalesce(w.box_office_penalty, 1.5) else 0 end
    + case when price_affinity_match then coalesce(w.price_affinity, 2) else 0 end
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
    case when festival_match then 'festival_gefolgt' end,
    case when favorite_signal > 0 then 'aehnliche_favoriten' end,
    case when view_signal > 0 then 'ansichtsverhalten' end,
    case when ticket_signal > 0 then 'ticketinteresse' end,
    case when share_signal > 0 then 'teilen_verhalten' end,
    case when calendar_signal > 0 then 'kalender_verhalten' end,
    case when impression_count > 0 then 'wiederholungsmalus' end,
    case when s.remaining_tickets_status = 'sold_out' then 'ausverkauft_malus' end,
    case when s.remaining_tickets_status = 'box_office_only' then 'abendkasse_malus' end,
    case when s.price_affinity_match then 'preisaffinitaet' end
  ], null)
from scored s
order by s.score desc, s.start_datetime
limit greatest(1, least(p_result_limit, 50));
$$;

grant execute on function recommended_events(int) to anon, authenticated;
