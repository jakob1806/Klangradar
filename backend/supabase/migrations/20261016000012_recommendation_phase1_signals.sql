-- Empfehlungssystem Phase 1 (Nutzeranfrage: "personalisiertes Empfehlungs-
-- system ... vergleichbar mit TikTok/Instagram/YouTube/Spotify"), Rest-Teil
-- nach der Analyse ohne Code-Änderung. Baut auf 20261016000011_home_feed_
-- behavior_ranking.sql auf (zeitlich gewichtete Verhaltenssignale,
-- Impression-Fatigue statt hartem Ausschluss — von einer parallelen Session
-- bereits umgesetzt, hier NICHT dupliziert). Ergänzt die drei echten Lücken:
--
-- 1. Eligibility Filtering / hartes negatives Signal: content_dismissals
--    ("Nicht interessiert") — bisher gab es nur "Folgen/Entfolgen", kein Weg,
--    ein Event/eine Venue/Person/Ensemble aktiv als "nicht relevant"
--    auszuschließen. Anders als impression_fatigue (weicher Malus) ist das
--    ein HARTER Ausschluss, wie in der Anfrage für "Ausblenden"/"Nicht
--    interessiert" gefordert.
-- 2. Teilen-Signal (event_shares) — Share.share() im Client rief bisher
--    nichts im Backend auf.
-- 3. Echtes Collaborative Filtering (cohort_recommended_events) — das
--    bestehende favorite_signal in recommended_events() ist inhaltsbasiert
--    (eigene Favoriten, gleiche Venue/Genre), nicht "andere Nutzer:innen mit
--    ähnlichem Geschmack mochten auch..." — das fehlte komplett.
--
-- Bewusst NICHT dupliziert (siehe Analyse-Nachricht): Kommentare, Blockieren,
-- Swipe-Skip, Video-Completion-Rate — passen strukturell nicht zu einer
-- kuratierten Konzert-Datenbank ohne nutzergenerierten Content.

-- "Nicht interessiert" / Ausblenden — polymorph über vier Entitätstypen
-- (Event selbst, oder eine Venue/Person/Ensemble komplett ausblenden, z.B.
-- "keine Kirchenmusik mehr" indirekt über wiederholtes Ausblenden derselben
-- Venue). reason ist frei bleibend (kein Enum) — anders als content_reports
-- (Datenqualitäts-Meldungen mit festem Grund-Katalog) geht es hier um reine
-- Präferenz, nicht um einen Fehler in den Daten.
create table if not exists content_dismissals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  entity_type text not null check (entity_type in ('event', 'venue', 'person', 'ensemble')),
  entity_id uuid not null,
  reason text,
  created_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);
create index if not exists idx_content_dismissals_user on content_dismissals(user_id, entity_type);
alter table content_dismissals enable row level security;
create policy "Nutzer verwaltet eigene Ausblendungen" on content_dismissals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Teilen — analog zu ticket_clicks, nur für eingeloggte Nutzer:innen (siehe
-- 20261016000009 zur selben Einschränkung bei ticket_clicks).
create table if not exists event_shares (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  shared_at timestamptz not null default now()
);
create index if not exists idx_event_shares_user on event_shares(user_id);
create index if not exists idx_event_shares_event on event_shares(event_id);
alter table event_shares enable row level security;
create policy "Nutzer verwaltet eigene Shares" on event_shares
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Generischer Klick auf Person/Ensemble/Venue/Genre — deckt "Klicks auf
-- Profile, Künstler, Kategorien oder Tags" aus der Anfrage ab. Ein Event-
-- Typ statt vier Spezialtabellen, weil es nur als Rohsignal für zukünftige
-- Auswertung gedacht ist (Phase 2), nicht für sofortiges Scoring.
create table if not exists content_clicks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  entity_type text not null check (entity_type in ('person', 'ensemble', 'venue', 'genre')),
  entity_id uuid not null,
  clicked_at timestamptz not null default now()
);
create index if not exists idx_content_clicks_user on content_clicks(user_id) where user_id is not null;
alter table content_clicks enable row level security;
-- Anonyme Klicks bewusst erlaubt (user_id nullable) — anders als
-- ticket_clicks/event_shares geht es hier um aggregierte Popularitäts-
-- Auswertung (Phase 2), nicht um personalisiertes Scoring einer konkreten
-- Person, daher kein Login nötig und kein Datenschutz-Mehrwert durch
-- Anmeldepflicht.
create policy "Jeder kann Klicks protokollieren" on content_clicks
  for insert with check (auth.uid() = user_id or user_id is null);
create policy "Nutzer sieht eigene Klicks" on content_clicks
  for select using (auth.uid() = user_id);

insert into home_feed_ranking_weights (key, weight, description) values
  ('share_behavior', 2.0, 'Zeitlich gewichtete Shares ähnlicher Events — stärkeres Intent-Signal als ein Klick')
on conflict (key) do update set weight = excluded.weight, description = excluded.description;

-- recommended_events() erneut neu definiert (baut auf der Version aus
-- 20261016000011 auf): + Teilen-Signal, + harter Ausschluss über
-- content_dismissals (Event selbst ODER dessen Venue/Mitwirkende
-- ausgeblendet). Diversitätsregeln/Impression-Fatigue aus 011 bleiben
-- unverändert.
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
    max(weight) filter (where key = 'share_behavior') as share_behavior,
    max(weight) filter (where key = 'impression_fatigue') as fatigue
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
    (select ln(1 + count(*)::numeric) from favorites f where f.event_id = e.id) as popularity_signal,
    (select count(*) from home_feed_impressions h
      where h.user_id = auth.uid() and h.event_id = e.id
        and h.module_key = 'fuer_dich' and h.shown_at >= now() - interval '14 days')::numeric as impression_count
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
    + favorite_signal * coalesce(w.favorite_behavior, 1.8)
    + view_signal * coalesce(w.view_behavior, 1.2)
    + ticket_signal * coalesce(w.ticket_behavior, 2.2)
    + share_signal * coalesce(w.share_behavior, 2.0)
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
    case when share_signal > 0 then 'teilen_verhalten' end,
    case when impression_count > 0 then 'wiederholungsmalus' end
  ], null)
from scored s
order by s.score desc, s.start_datetime
limit greatest(1, least(p_result_limit, 50));
$$;

grant execute on function recommended_events(int) to anon, authenticated;

-- discovery_events() und entity_news_events() bekommen denselben harten
-- Ausschluss über content_dismissals (Eligibility Filtering muss laut
-- Anfrage IMMER greifen, unabhängig vom Modul/Score).
create or replace function discovery_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[]
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_has_seeds boolean;
begin
  if v_uid is null then
    return;
  end if;

  select exists (
    select 1 from events e
    where e.embedding is not null
      and e.id in (
        select event_id from favorites where user_id = v_uid
        union
        select event_id from event_views where user_id = v_uid
      )
  ) into v_has_seeds;

  if not v_has_seeds then
    return;
  end if;

  return query
    with seed_ids as (
      (
        select event_id, created_at as ts from favorites where user_id = v_uid
        union
        select event_id, viewed_at as ts from event_views where user_id = v_uid
      )
      order by ts desc
      limit 5
    ),
    seed_embeddings as (
      select e.embedding from events e
      join seed_ids s on s.event_id = e.id
      where e.embedding is not null
    ),
    already_seen as (
      select event_id from favorites where user_id = v_uid
      union
      select event_id from event_views where user_id = v_uid
    )
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
      and e.start_datetime >= now()
      and e.embedding is not null
      and e.id not in (select event_id from already_seen)
      and e.id not in (select entity_id from content_dismissals where user_id = v_uid and entity_type = 'event')
      and e.venue_id not in (select entity_id from content_dismissals where user_id = v_uid and entity_type = 'venue')
      and not (
        exists (
          select 1 from user_favorite_venues ufv
          where ufv.venue_id = e.venue_id and ufv.user_id = v_uid
        )
        and exists (
          select 1 from event_participants ep
          join user_favorite_persons ufp on ufp.person_id = ep.person_id
          where ep.event_id = e.id and ufp.user_id = v_uid
        )
      )
    order by (select min(e.embedding <=> se.embedding) from seed_embeddings se) asc
    limit p_result_limit;
end;
$$;

grant execute on function discovery_events(int) to anon, authenticated;

create or replace function entity_news_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[]
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return;
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
      and e.start_datetime >= now()
      and e.created_at >= now() - interval '3 days'
      and e.id not in (select entity_id from content_dismissals where user_id = v_uid and entity_type = 'event')
      and e.venue_id not in (select entity_id from content_dismissals where user_id = v_uid and entity_type = 'venue')
      and (
        exists (select 1 from user_favorite_venues ufv where ufv.venue_id = e.venue_id and ufv.user_id = v_uid)
        or exists (
          select 1 from event_participants ep
          join user_favorite_persons ufp on ufp.person_id = ep.person_id
          where ep.event_id = e.id and ufp.user_id = v_uid
        )
        or exists (
          select 1 from event_participants ep
          join user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
          where ep.event_id = e.id and ufe.user_id = v_uid
        )
      )
    order by e.created_at desc, e.start_datetime
    limit p_result_limit;
end;
$$;

grant execute on function entity_news_events(int) to anon, authenticated;

-- Echtes Collaborative Filtering (Abschnitt 5 der Anfrage: "bei ähnlichen
-- Nutzern erfolgreiche Inhalte") — Kohorte = andere Nutzer:innen, deren
-- Favoriten mit den eigenen mindestens 2 gemeinsame Venues/Genres/Personen/
-- Ensembles teilen. Zeigt Events, die diese Kohorte favorisiert hat und die
-- Person selbst noch nicht kennt (nicht favorisiert/angesehen/ausgeblendet).
-- Reine SQL-Kohortenabfrage statt ML — angemessen für die aktuelle Nutzer-
-- basis (siehe Analyse-Nachricht, Annahme 2: kein Vektor-/ML-Infrastruktur-
-- Neubau ohne Not).
create or replace function cohort_recommended_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[]
)
language sql
stable
as $$
with my_favorite_events as (
  select f.event_id, e.venue_id,
    array_agg(distinct eg.genre_id) filter (where eg.genre_id is not null) as genre_ids
  from favorites f
  join events e on e.id = f.event_id
  left join event_genres eg on eg.event_id = e.id
  where f.user_id = auth.uid()
  group by f.event_id, e.venue_id
), similar_users as (
  -- Nutzer:innen (nicht ich selbst), die mind. 2 meiner favorisierten
  -- Events ODER Events an denselben Venues favorisiert haben.
  select f2.user_id, count(*) as overlap_count
  from favorites f2
  join my_favorite_events mfe on mfe.event_id = f2.event_id
  where f2.user_id != auth.uid()
  group by f2.user_id
  having count(*) >= 1
  union
  select f2.user_id, count(distinct f2.event_id) as overlap_count
  from favorites f2
  join events e2 on e2.id = f2.event_id
  join my_favorite_events mfe on mfe.venue_id = e2.venue_id
  where f2.user_id != auth.uid()
  group by f2.user_id
  having count(distinct f2.event_id) >= 2
), already_known as (
  select event_id from favorites where user_id = auth.uid()
  union
  select event_id from event_views where user_id = auth.uid()
)
select
  e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status, e.start_datetime,
  v.id,
  jsonb_build_object('name', v.name),
  coalesce(
    (select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
      from event_genres eg join genres g on g.id = eg.genre_id where eg.event_id = e.id),
    '[]'::jsonb
  ),
  e.image_urls
from events e
join venues v on v.id = e.venue_id
join favorites f on f.event_id = e.id
join similar_users su on su.user_id = f.user_id
where auth.uid() is not null
  and e.status = 'scheduled'
  and e.start_datetime >= now()
  and e.id not in (select event_id from already_known)
  and e.id not in (select entity_id from content_dismissals where user_id = auth.uid() and entity_type = 'event')
  and e.venue_id not in (select entity_id from content_dismissals where user_id = auth.uid() and entity_type = 'venue')
group by e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status,
  e.start_datetime, v.id, v.name, e.image_urls
order by sum(su.overlap_count) desc, count(distinct f.user_id) desc, e.start_datetime
limit greatest(1, least(p_result_limit, 30));
$$;

grant execute on function cohort_recommended_events(int) to anon, authenticated;
