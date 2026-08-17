-- Home-Feed Phase B (docs/08-home-feed-recommendation-algorithm.md,
-- Abschnitt 9 + 10) — Nutzeranfrage: "stelle alles fertig, was noch aus dem
-- design dokument übrig ist". Ergänzt das in Abschnitt 9 skizzierte Schema
-- und verdrahtet es in recommended_events() sowie drei neuen RPCs
-- (hero_event, entity_news_events, festival_events) für die drei noch
-- fehlenden Module aus Abschnitt 3 (Hero-Personalisierung, "Dein
-- Ort/Ensemble hat Neuigkeiten", Saisonal/Festival).
--
-- Eine Korrektur ggü. der Doku beim Verifizieren: Abschnitt 9 listet
-- "profile_interest_ensembles" als fehlend — das ist überholt. Ensemble-
-- Interesse existiert bereits als user_favorite_ensembles
-- (20260715000011_profiles_and_personalization.sql) und wird in
-- recommended_events() schon verwendet (w_ensemble). Hier NICHT nochmal
-- angelegt.
--
-- Ticketklick-/Verweildauer-Signal (Abschnitt 4.1, eigene Gewichtszeilen im
-- Entwurf) werden hier bewusst NICHT als zusätzliche additive Summanden
-- umgesetzt, sondern als zusätzliche Evidenz in die schon bestehenden
-- Venue-/Personen-/Ensemble-Interesse-Signale gefaltet (ein Ticketklick
-- oder eine lange Verweildauer bei einem Event an Venue X bzw. mit
-- Mitwirkender Y zählt wie "Venue/Person favorisiert"). Das vermeidet eine
-- immer weiter wachsende Liste kaum noch unterscheidbarer Summanden und
-- bleibt trotzdem literal am Ziel der Doku: die neuen Signale beeinflussen
-- jetzt nachweisbar das Scoring statt nur Daten zu sammeln.

-- Verweildauer — event_views existiert, aber ohne Dauer.
alter table event_views add column if not exists duration_seconds int;

-- Ticketklicks — nur für eingeloggte Nutzer:innen erfasst (gleiche
-- Einschränkung wie event_views clientseitig schon hat: "if (event != null
-- && userId != null)" in event_detail_screen.dart) statt der in der Doku
-- skizzierten nullable user_id, damit RLS "auth.uid() = user_id" konsistent
-- mit allen anderen Tracking-Tabellen bleibt.
create table if not exists ticket_clicks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  clicked_at timestamptz not null default now()
);
create index if not exists idx_ticket_clicks_user on ticket_clicks(user_id);
create index if not exists idx_ticket_clicks_event on ticket_clicks(event_id);
alter table ticket_clicks enable row level security;
create policy "Nutzer verwaltet eigene Ticketklicks" on ticket_clicks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Impression-Log gegen Tag-zu-Tag-Wiederholung (Abschnitt 5.4) — nur für
-- Hero und "Für dich" relevant (die einzigen Module mit einer Sliding-
-- Window-Regel laut Doku), aber generisch über module_key für spätere
-- weitere Module.
create table if not exists home_feed_impressions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  module_key text not null,
  shown_at timestamptz not null default now()
);
create index if not exists idx_home_feed_impressions_lookup
  on home_feed_impressions(user_id, module_key, shown_at desc);
alter table home_feed_impressions enable row level security;
create policy "Nutzer verwaltet eigene Feed-Impressionen" on home_feed_impressions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Festival-Zeitfenster für automatische Modul-Aktivierung (Abschnitt 4.4).
alter table festivals add column if not exists start_date date;
alter table festivals add column if not exists end_date date;

-- Neue Gewichte fürs Hero-Modul (Abschnitt 4.2: Bildbonus + Wiederholungs-
-- Malus) in derselben Konfigurationstabelle wie die bestehenden Signale.
insert into home_feed_ranking_weights (key, weight, description) values
  ('hero_image_bonus', 2, 'Bonus für Hero-Kandidaten mit echtem Eventbild'),
  ('hero_repeat_malus', 4, 'Abzug wenn dasselbe Event/dieselbe Venue in den letzten 3 Tagen schon Hero war')
on conflict (key) do nothing;

-- recommended_events(): dieselbe Formel wie in 20261013000015, erweitert um
-- (a) Ticketklick-/Verweildauer-Evidenz in has_venue_match/has_person_match/
-- has_ensemble_match (siehe Kommentar oben) und (b) Ausschluss von Events,
-- die dieser Person in den letzten 7 Tagen schon im "Für dich"-Modul
-- gezeigt wurden (Diversitätsregel 4, Abschnitt 5) — geloggt vom Client
-- über home_feed_impressions(module_key='fuer_dich').
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
  w_work numeric;
  w_venue numeric;
  w_person numeric;
  w_ensemble numeric;
  w_popularity numeric;
  w_time_decay_days numeric;
begin
  select weight into w_genre from home_feed_ranking_weights where key = 'genre_interest';
  select weight into w_work from home_feed_ranking_weights where key = 'work_interest';
  select weight into w_venue from home_feed_ranking_weights where key = 'venue_interest';
  select weight into w_person from home_feed_ranking_weights where key = 'person_interest';
  select weight into w_ensemble from home_feed_ranking_weights where key = 'ensemble_interest';
  select weight into w_popularity from home_feed_ranking_weights where key = 'popularity_scale';
  select weight into w_time_decay_days from home_feed_ranking_weights where key = 'time_decay_divisor_days';

  return query
    with recently_shown as (
      select event_id from home_feed_impressions
      where user_id = v_uid and module_key = 'fuer_dich' and shown_at >= now() - interval '7 days'
    ),
    scored as (
      select
        e.id, e.slug, e.title, e.subtitle, e.is_free,
        e.remaining_tickets_status, e.start_datetime,
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
        (v_uid is not null and exists (
          select 1 from event_works ew
          join user_favorite_works ufw on ufw.work_id = ew.work_id
          where ew.event_id = e.id and ufw.user_id = v_uid
        )) as has_work_match,
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
          or exists (
            select 1 from ticket_clicks tc
            join events e2 on e2.id = tc.event_id
            where e2.venue_id = e.venue_id and tc.user_id = v_uid
          )
        )) as has_venue_match,
        (v_uid is not null and (
          exists (
            select 1 from event_participants ep
            join user_favorite_persons ufp on ufp.person_id = ep.person_id
            where ep.event_id = e.id and ufp.user_id = v_uid
          )
          or exists (
            -- dieselbe Person tritt auch bei einem Event auf, für das die
            -- Person schon einen Ticketklick gemacht hat
            select 1 from event_participants ep_e
            join event_participants ep_c on ep_c.person_id = ep_e.person_id
            join ticket_clicks tc on tc.event_id = ep_c.event_id and tc.user_id = v_uid
            where ep_e.event_id = e.id
          )
          or exists (
            -- ...oder ein Event mit >=15s Verweildauer angesehen hat
            select 1 from event_participants ep_e
            join event_participants ep_c on ep_c.person_id = ep_e.person_id
            join event_views ev on ev.event_id = ep_c.event_id and ev.user_id = v_uid and ev.duration_seconds >= 15
            where ep_e.event_id = e.id
          )
        )) as has_person_match,
        (v_uid is not null and (
          exists (
            select 1 from event_participants ep
            join user_favorite_ensembles ufe on ufe.ensemble_id = ep.ensemble_id
            where ep.event_id = e.id and ufe.user_id = v_uid
          )
          or exists (
            select 1 from event_participants ep_e
            join event_participants ep_c on ep_c.ensemble_id = ep_e.ensemble_id
            join ticket_clicks tc on tc.event_id = ep_c.event_id and tc.user_id = v_uid
            where ep_e.event_id = e.id
          )
          or exists (
            select 1 from event_participants ep_e
            join event_participants ep_c on ep_c.ensemble_id = ep_e.ensemble_id
            join event_views ev on ev.event_id = ep_c.event_id and ev.user_id = v_uid and ev.duration_seconds >= 15
            where ep_e.event_id = e.id
          )
        )) as has_ensemble_match,
        (select ln(1 + count(*)::float) from favorites f where f.event_id = e.id) as popularity_raw
      from events e
      join venues v on v.id = e.venue_id
      where e.status = 'scheduled' and e.start_datetime >= now()
        and (v_uid is null or e.id not in (select event_id from recently_shown))
    )
    select
      s.id, s.slug, s.title, s.subtitle, s.is_free,
      s.remaining_tickets_status, s.start_datetime,
      s.venue_id, s.venues, s.event_genres, s.image_urls,
      round((
        (case when has_genre_match then w_genre else 0 end)
        + (case when has_work_match then w_work else 0 end)
        + (case when has_venue_match then w_venue else 0 end)
        + (case when has_person_match then w_person else 0 end)
        + (case when has_ensemble_match then w_ensemble else 0 end)
        + coalesce(popularity_raw, 0) * w_popularity
        - (extract(epoch from (s.start_datetime - now())) / 86400.0 / w_time_decay_days)
      )::numeric, 3) as rank_score,
      array_remove(array[
        case when has_genre_match then 'genre_interesse' end,
        case when has_work_match then 'werk_interesse' end,
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

-- Hero (Abschnitt 4.2): dieselbe Formel wie "Für dich" via recommended_
-- events(), plus Bildbonus und Wiederholungs-Malus, LIMIT 1. Ohne Login
-- bleibt es beim bisherigen, unpersonalisierten "nächstes Event" (Cold-
-- Start-Stufe 0, Abschnitt 6) — kein Sonderfall im Client nötig.
create or replace function hero_event()
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
  w_image_bonus numeric;
  w_repeat_malus numeric;
begin
  if v_uid is null then
    return query
      select e.id, e.slug, e.title, e.subtitle, e.is_free,
        e.remaining_tickets_status, e.start_datetime, v.id,
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
      where e.status = 'scheduled' and e.start_datetime >= now()
      order by e.start_datetime
      limit 1;
    return;
  end if;

  select weight into w_image_bonus from home_feed_ranking_weights where key = 'hero_image_bonus';
  select weight into w_repeat_malus from home_feed_ranking_weights where key = 'hero_repeat_malus';

  return query
    with recent_hero as (
      select event_id from home_feed_impressions
      where user_id = v_uid and module_key = 'hero' and shown_at >= now() - interval '3 days'
    )
    select
      c.id, c.slug, c.title, c.subtitle, c.is_free, c.remaining_tickets_status,
      c.start_datetime, c.venue_id, c.venues, c.event_genres, c.image_urls
    from recommended_events(30) c
    order by
      (
        c.rank_score
        + (case when c.image_urls is not null and array_length(c.image_urls, 1) > 0 then w_image_bonus else 0 end)
        - (case when exists (
            select 1 from recent_hero rh
            join events e2 on e2.id = rh.event_id
            where rh.event_id = c.id or e2.venue_id = c.venue_id
          ) then w_repeat_malus else 0 end)
      ) desc,
      c.start_datetime
    limit 1;
end;
$$;

grant execute on function hero_event() to anon, authenticated;

-- "Dein Ort/Ensemble hat Neuigkeiten" (Abschnitt 3.5): neu hinzugekommene
-- Events (letzte 3 Tage, gleiches Fenster wie notify-followed-entity-
-- events) an gefolgten Venues/Personen/Ensembles
-- (user_favorite_venues/_persons/_ensembles — dieselben Tabellen, die auch
-- die Push-Benachrichtigung dafür speisen). Ohne Login leer.
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

-- Saisonal/Festival (Abschnitt 4.4): Events des Festivals mit dem
-- nächstliegenden aktiven Zeitfenster (now() zwischen start_date/end_date).
-- Kein aktives Festival -> leeres Ergebnis, Modul wird vom Client
-- übersprungen (wie jedes andere Modul mit zu wenigen Kandidaten).
create or replace function festival_events(p_result_limit int default 10)
returns table (
  id uuid, slug text, title text, subtitle text, is_free boolean,
  remaining_tickets_status text, start_datetime timestamptz, venue_id uuid,
  venues jsonb, event_genres jsonb, image_urls text[],
  festival_name text
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  v_festival_id uuid;
  v_festival_name text;
begin
  select f.id, f.name into v_festival_id, v_festival_name
  from festivals f
  where f.start_date is not null and f.end_date is not null
    and current_date between f.start_date and f.end_date
  order by f.end_date asc
  limit 1;

  if v_festival_id is null then
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
      e.image_urls,
      v_festival_name
    from events e
    join venues v on v.id = e.venue_id
    where e.festival_id = v_festival_id
      and e.status = 'scheduled'
      and e.start_datetime >= now()
    order by e.start_datetime
    limit p_result_limit;
end;
$$;

grant execute on function festival_events(int) to anon, authenticated;
