-- Nutzeranfrage: "mach das Homescreen-RPC-Bündeln auch" (Nachtrag zum
-- Perf-Audit, siehe home_providers.dart-Kommentar). homeDataProvider löste
-- bisher 11 separate Requests aus (8 RPCs + 3 rohe Table-Selects), parallel
-- per Future.wait, aber trotzdem 11 einzelne HTTP-Roundtrips plus einen 12.
-- für die Komponisten-Diversität. home_feed_bundle() ruft dieselben,
-- unverändert bestehenden Bausteine (hero_event/recommended_events/
-- favorite_events_home/followed_events/discovery_events/
-- entity_news_events/festival_events/popular_events) sowie die drei rohen
-- Abfragen (heute/ausverkauft/kostenlos) serverseitig in EINER Funktion auf
-- und liefert zusätzlich gleich die Komponisten-IDs für die
-- Diversitätsregel mit — macht aus 12 Client-Requests einen einzigen.
--
-- Bewusst keine Neuimplementierung der Scoring-/Ranking-Logik: die
-- Bausteine bleiben exakt dieselben Funktionen mit denselben Parametern wie
-- bisher im Client aufgerufen (inkl. der bestehenden Eigenheit, dass
-- popular_events() ohne p_city_id aufgerufen wird und damit auf
-- munich_city_id() zurückfällt — unverändertes Verhalten, keine
-- Verhaltensänderung durch dieses Bündeln).
--
-- "Heute"-Fenster kommt weiterhin vom Client (p_today_start/p_today_end),
-- nicht neu in SQL berechnet — Munich-Tagesgrenzen client-seitig über
-- MunichTime zu bestimmen hat schon einmal einen .toUtc()-Bug gehabt (siehe
-- Kommentar in calendar_providers.dart); dieselbe Logik hier zu duplizieren
-- wäre ein unnötiges zweites Fehlerrisiko.
--
-- Kein SECURITY DEFINER: läuft als reine Hülle unter der Berechtigung des
-- aufrufenden Nutzers, genau wie die einzeln aufgerufenen Bausteine vorher
-- (die nutzen intern alle schon auth.uid()) — keine Rechteausweitung.
create or replace function home_feed_bundle(
  p_now timestamptz,
  p_today_start timestamptz,
  p_today_end timestamptz,
  p_city_id uuid default null,
  p_recommended_limit int default 24,
  p_favorite_limit int default 20,
  p_followed_limit int default 20,
  p_discovery_limit int default 10,
  p_entity_news_limit int default 10,
  p_few_left_limit int default 10,
  p_festival_limit int default 10,
  p_free_limit int default 10,
  p_popular_limit int default 10
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_hero jsonb;
  v_heute jsonb;
  v_recommended jsonb;
  v_favorites jsonb;
  v_followed jsonb;
  v_discovery jsonb;
  v_entity_news jsonb;
  v_few_left jsonb;
  v_festival jsonb;
  v_free jsonb;
  v_popular jsonb;
  v_event_ids uuid[];
  v_composer_map jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_hero
    from hero_event() t;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_recommended
    from recommended_events(p_recommended_limit, p_city_id) t;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_favorites
    from favorite_events_home(p_favorite_limit) t;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_followed
    from followed_events(p_followed_limit) t;
  -- Explizit 2 Argumente (auch wenn p_city_id null ist): discovery_events
  -- ist aktuell in zwei Overloads deployt (1 Arg / 2 Argumente mit
  -- p_city_id default munich_city_id()) — ein Aufruf mit nur einem
  -- Argument ist seit dem zweiten Overload mehrdeutig und schlägt fehl
  -- ("function discovery_events(integer) is not unique", live geprüft).
  -- Betrifft auch den bisherigen Direktaufruf aus dem Client, sobald keine
  -- Stadt ausgewählt ist (dann ohne p_city_id-Parameter) — ein
  -- vorbestehender Bug, unabhängig von diesem Bündeln. Null hält das
  -- bisher beabsichtigte Verhalten (keine Stadt-Einschränkung bei der
  -- Ähnlichkeitssuche).
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_discovery
    from discovery_events(p_discovery_limit, null::uuid) t;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_entity_news
    from entity_news_events(p_entity_news_limit) t;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_festival
    from festival_events(p_festival_limit) t;
  -- Kein p_city_id: siehe Kommentar oben, unverändertes Verhalten.
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_popular
    from popular_events(p_popular_limit) t;

  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_heute
  from (
    select
      e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status,
      e.discount_info, e.start_datetime, e.venue_detail, e.image_urls,
      jsonb_build_object('name', v.name) as venues,
      coalesce(
        (select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
         from event_genres eg join genres g on g.id = eg.genre_id
         where eg.event_id = e.id),
        '[]'::jsonb
      ) as event_genres
    from events e
    join venues v on v.id = e.venue_id
    where e.status = 'scheduled'
      and e.start_datetime >= p_today_start
      and e.start_datetime < p_today_end
    order by e.start_datetime
  ) t;

  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_few_left
  from (
    select
      e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status,
      e.discount_info, e.start_datetime, e.venue_detail, e.image_urls,
      jsonb_build_object('name', v.name) as venues,
      coalesce(
        (select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
         from event_genres eg join genres g on g.id = eg.genre_id
         where eg.event_id = e.id),
        '[]'::jsonb
      ) as event_genres
    from events e
    join venues v on v.id = e.venue_id
    where e.status = 'scheduled'
      and e.remaining_tickets_status = 'few_left'
      and e.start_datetime >= p_now
    order by e.start_datetime
    limit p_few_left_limit
  ) t;

  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_free
  from (
    select
      e.id, e.slug, e.title, e.subtitle, e.is_free, e.remaining_tickets_status,
      e.discount_info, e.start_datetime, e.venue_detail, e.image_urls,
      jsonb_build_object('name', v.name) as venues,
      coalesce(
        (select jsonb_agg(jsonb_build_object('genres', jsonb_build_object('slug', g.slug)))
         from event_genres eg join genres g on g.id = eg.genre_id
         where eg.event_id = e.id),
        '[]'::jsonb
      ) as event_genres
    from events e
    join venues v on v.id = e.venue_id
    where e.status = 'scheduled'
      and e.is_free = true
      and e.start_datetime >= p_now
    order by e.start_datetime
    limit p_free_limit
  ) t;

  -- Komponisten je Event für die client-seitige Diversitätsregel (max. 1
  -- Event desselben Komponisten pro Modul) — bisher ein 12. Request
  -- (_loadComposerIdsByEvent) über die Vereinigung aller Kandidaten-IDs,
  -- jetzt gleich hier über dieselbe Vereinigung berechnet.
  select array_agg(distinct (x->>'id')::uuid) into v_event_ids
  from (
    select x from jsonb_array_elements(v_hero) x
    union all select x from jsonb_array_elements(v_heute) x
    union all select x from jsonb_array_elements(v_recommended) x
    union all select x from jsonb_array_elements(v_favorites) x
    union all select x from jsonb_array_elements(v_followed) x
    union all select x from jsonb_array_elements(v_discovery) x
    union all select x from jsonb_array_elements(v_entity_news) x
    union all select x from jsonb_array_elements(v_few_left) x
    union all select x from jsonb_array_elements(v_festival) x
    union all select x from jsonb_array_elements(v_free) x
    union all select x from jsonb_array_elements(v_popular) x
  ) all_ids;

  select coalesce(jsonb_object_agg(event_id, composer_ids), '{}'::jsonb) into v_composer_map
  from (
    select ew.event_id::text as event_id,
      jsonb_agg(distinct w.composer_id) as composer_ids
    from event_works ew
    join works w on w.id = ew.work_id
    where v_event_ids is not null
      and ew.event_id = any(v_event_ids)
      and w.composer_id is not null
    group by ew.event_id
  ) c;

  return jsonb_build_object(
    'hero', v_hero,
    'heute', v_heute,
    'empfehlungen', v_recommended,
    'favoriten', v_favorites,
    'gefolgt', v_followed,
    'entdecken', v_discovery,
    'entityNews', v_entity_news,
    'ausverkauft', v_few_left,
    'festival', v_festival,
    'kostenlos', v_free,
    'beliebt', v_popular,
    'composerIdsByEvent', v_composer_map
  );
end;
$$;

grant execute on function home_feed_bundle(
  timestamptz, timestamptz, timestamptz, uuid, int, int, int, int, int, int, int, int, int
) to anon, authenticated;
