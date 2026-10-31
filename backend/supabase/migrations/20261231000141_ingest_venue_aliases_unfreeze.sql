-- Erstellt von Claude Code (Nutzerwunsch 31.10.2026: Importquellen prüfen).
--
-- 1. find_matching_venue berücksichtigt jetzt die gepflegten Venue-Aliasse
--    (entity_aliases). Bisher verglich die Funktion nur venues.name per
--    Trigramm – "Bayerische Staatsoper" (Alias von "Nationaltheater
--    München") oder "Elbphilharmonie Hamburg" (Alias von "Elbphilharmonie –
--    Großer Saal") fanden nichts, die Termine wurden mit "no venue match"
--    verworfen (z. B. Concerti München, Hamburgische Staatsoper, NDR EO).
--    Exakter Alias = 1.0; bei Gleichstand gewinnt der Große Saal bzw. die
--    Spielstätte mit den meisten Terminen. Der Stadtfilter im Import bleibt.
-- 2. Eingefrorene Quellen wieder freigeben: Der Import speicherte den
--    Inhalts-Hash bisher VOR dem Schreiben. Brach der Lauf danach ab
--    (Zeitlimit), galt die Quelle als "unverändert" und wurde nie wieder
--    verarbeitet (z. B. Münchner Rundfunkorchester, BR-Chor). Der Code
--    speichert den Hash jetzt erst nach erfolgreichem Schreiben; hier
--    werden die alten Hashes einmalig verworfen.
-- 3. Wiener Symphoniker antworten bei häufigen Abrufen mit HTTP 429 –
--    höchstens alle 6 Stunden abrufen.

set statement_timeout = '10min';

create or replace function public.find_matching_venue(
  p_name text, p_similarity_threshold numeric default 0.4, p_result_limit integer default 3
)
returns table(id uuid, name text, similarity numeric, photo_url text)
language sql stable set search_path = public as $$
  with c as (
    select v.id,
      greatest(
        similarity(v.name, p_name),
        coalesce((select max(case when lower(btrim(a.alias)) = lower(btrim(p_name)) then 1 else similarity(a.alias, p_name) end)
                  from entity_aliases a where a.entity_type = 'venue' and a.entity_id = v.id), 0)
      )::numeric as sim
    from venues v
  )
  select v.id, v.name, c.sim, v.photo_url
  from c join venues v on v.id = c.id
  where c.sim >= p_similarity_threshold
  order by c.sim desc,
    (v.name ilike '%Großer Saal%') desc,
    (select count(*) from events e where e.venue_id = v.id) desc
  limit p_result_limit;
$$;

update public.sources
   set config = jsonb_set(config, '{httpCache}', coalesce(config->'httpCache', '{}'::jsonb) - 'lastBodyHash' - 'etag' - 'lastModified')
 where status = 'active' and config ? 'httpCache';

update public.sources
   set crawl_frequency_minutes = greatest(crawl_frequency_minutes, 360)
 where name = 'Wiener Symphoniker';

-- ===========================================================================
-- Erweiterung (Nutzerwunsch 31.10.2026: Reparaturen, Spielstätten, Bilder,
-- neue Quellen, Überwachung)
-- ===========================================================================

-- 4. Saal-/Haus-Namen der Quellen als Aliasse (häufigste "no venue match").
insert into public.entity_aliases (entity_type, entity_id, alias)
select 'venue', v.id, a.alias
from (values
  ('Muffathalle', 'Muffatwerk'),
  ('Wiener Konzerthaus – Berio-Saal', 'Buffet Berio-Saal'),
  ('Alte Oper Frankfurt – Mozart Saal', 'Mozart Saal'),
  ('Alte Oper Frankfurt – Großer Saal', 'Ganzes Haus'),
  ('Philharmonie Berlin – Kammermusiksaal', 'Kammermusiksaal Oberes Foyer'),
  ('Philharmonie Berlin – Großer Saal', 'Foyer Großer Saal'),
  ('HfMDK Frankfurt', 'HfMDK'),
  ('Konzerthaus Berlin – Großer Saal', 'Gendarmenmarkt')
) as a(venue_name, alias)
join public.venues v on v.name = a.venue_name
on conflict (entity_type, entity_id, alias) do nothing;

-- 5. Fehlende Spielstätten mit regelmäßigen Klassik-Terminen.
insert into public.venues (slug, name, address_street, address_zip, address_city, location, city_id)
select v.slug, v.name, v.street, v.zip, v.city,
  st_setsrid(st_makepoint(v.lng, v.lat), 4326)::geography,
  (select id from public.regions where type = 'city' and slug = v.region)
from (values
  ('bayerisches-nationalmuseum', 'Bayerisches Nationalmuseum', 'Prinzregentenstraße 3', '80538', 'München', 11.59118, 48.14334, 'munich'),
  ('ernst-deutsch-theater', 'Ernst Deutsch Theater', 'Friedrich-Schütter-Platz 1', '22087', 'Hamburg', 10.02286, 53.56334, 'hamburg')
) as v(slug, name, street, zip, city, lng, lat, region)
where not exists (select 1 from public.venues x where x.slug = v.slug or x.name = v.name);

-- 6. Bilder nicht mehr im Import-Lauf verarbeiten (siehe write.ts), sondern
--    im Job enrich-entity-images – für alle aktiven Quellen.
update public.sources
   set config = coalesce(config, '{}'::jsonb) || '{"deferImageEnrichment": true}'::jsonb
 where status = 'active';

-- 7. Neue Quelle: Münchner Symphoniker (Konzertliste mit Datum als
--    data-Attribut, Ort, Dirigent/Solisten). robots.txt erlaubt den Abruf;
--    Termine außerhalb Münchens fallen über den Stadtfilter weg.
insert into public.sources (name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config)
select 'Münchner Symphoniker – Konzerte', 'scrape', 'https://www.muenchner-symphoniker.de/index.php/de/events', null,
  (select id from public.regions where type = 'city' and slug = 'munich'), 720,
  'robots.txt geprüft (31.10.2026): Konzertseite nicht disallowed.',
  'active',
  '{
    "itemSelector": ".event-row",
    "titleSelector": ".col-md-5 .event-title h3 span",
    "dateSelector": ":scope",
    "dateAttribute": "data-event-date",
    "timeSelector": ".col-sm-8 .event-date-time",
    "venueSelector": ".col-sm-8 .event-location",
    "urlSelector": ".col-md-2 .event-link a",
    "descriptionSelector": ".col-md-5 .event-soloists",
    "baseUrl": "https://www.muenchner-symphoniker.de",
    "autoPublish": true,
    "deferImageEnrichment": true
  }'::jsonb
where not exists (select 1 from public.sources where url = 'https://www.muenchner-symphoniker.de/index.php/de/events');

-- 8. Überwachung der Importquellen (Admin → Quellen-Gesundheit).
create or replace function public.admin_import_health()
returns table (
  source_id uuid, name text, type text, status text, city text,
  last_success_at timestamptz, days_since_success int,
  runs_7d int, failed_7d int, timeouts_7d int, found_7d int, created_7d int,
  upcoming int, top_error text, health text
)
language sql stable security definer set search_path = public as $$
  with r as (
    select ir.source_id,
      count(*)::int runs,
      count(*) filter (where ir.status = 'failed')::int failed,
      count(*) filter (where ir.errors::text like '%überschritt 30 Minuten%')::int timeouts,
      coalesce(sum(ir.events_found), 0)::int found,
      coalesce(sum(ir.events_created), 0)::int created
    from ingestion_runs ir
    where ir.started_at > now() - interval '7 days'
    group by ir.source_id
  ),
  errs as (
    select distinct on (ir.source_id) ir.source_id, left(e.err, 200) err
    from ingestion_runs ir
    cross join lateral jsonb_array_elements_text(coalesce(ir.errors, '[]'::jsonb)) e(err)
    where ir.started_at > now() - interval '7 days'
      and e.err not like 'Diagnostic%' and e.err not like '%überschritt 30 Minuten%'
    order by ir.source_id, ir.started_at desc
  ),
  up as (
    select e.source_id, count(*)::int n
    from events e
    where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out') and e.source_id is not null
    group by e.source_id
  )
  select s.id, s.name, s.type, s.status, rg.slug,
    s.last_success_at,
    case when s.last_success_at is null then null else (extract(epoch from now() - s.last_success_at) / 86400)::int end,
    coalesce(r.runs, 0), coalesce(r.failed, 0), coalesce(r.timeouts, 0), coalesce(r.found, 0), coalesce(r.created, 0),
    coalesce(up.n, 0), errs.err,
    case
      when s.status <> 'active' then 'paused'
      when s.last_success_at is null or s.last_success_at < now() - interval '3 days' then 'error'
      when coalesce(r.runs, 0) > 0 and coalesce(r.failed, 0) * 2 > r.runs then 'warn'
      when coalesce(r.found, 0) > 0 and coalesce(up.n, 0) = 0 then 'warn'
      else 'ok'
    end
  from sources s
  left join regions rg on rg.id = s.city_id
  left join r on r.source_id = s.id
  left join errs on errs.source_id = s.id
  left join up on up.source_id = s.id
  where is_admin_or_editor()
  order by case when s.status <> 'active' then 3 else 0 end,
    case when s.last_success_at is null or s.last_success_at < now() - interval '3 days' then 0
         when coalesce(r.runs, 0) > 0 and coalesce(r.failed, 0) * 2 > r.runs then 1 else 2 end,
    s.name;
$$;
revoke all on function public.admin_import_health() from public, anon;
grant execute on function public.admin_import_health() to authenticated;

-- Spielstätten, die der Import nicht zuordnen konnte (für "Anlegen" bzw.
-- "Als Alias zuordnen" im Admin).
create or replace function public.admin_unmatched_venues(p_days int default 14)
returns table (venue_name text, city text, occurrences int, sources text, example_event text)
language sql stable security definer set search_path = public as $$
  with hits as (
    select (regexp_match(e.err, 'no venue match for ''([^'']+)'''))[1] as venue_name,
           (regexp_match(e.err, '^"(.*)": no venue match'))[1] as event_title,
           s.name as source_name, rg.slug as city
    from ingestion_runs ir
    join sources s on s.id = ir.source_id
    left join regions rg on rg.id = s.city_id
    cross join lateral jsonb_array_elements_text(coalesce(ir.errors, '[]'::jsonb)) e(err)
    where ir.started_at > now() - make_interval(days => least(greatest(coalesce(p_days, 14), 1), 60))
      and e.err like '%no venue match for%'
  )
  select h.venue_name, h.city, count(*)::int,
    string_agg(distinct h.source_name, ', '), min(h.event_title)
  from hits h
  where is_admin_or_editor() and h.venue_name is not null
  group by h.venue_name, h.city
  order by 3 desc
  limit 100;
$$;
revoke all on function public.admin_unmatched_venues(int) from public, anon;
grant execute on function public.admin_unmatched_venues(int) to authenticated;

create or replace function public.admin_add_venue_alias(p_venue_id uuid, p_alias text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  insert into entity_aliases (entity_type, entity_id, alias)
  values ('venue', p_venue_id, btrim(p_alias))
  on conflict (entity_type, entity_id, alias) do nothing;
end;
$$;
revoke all on function public.admin_add_venue_alias(uuid, text) from public, anon;
grant execute on function public.admin_add_venue_alias(uuid, text) to authenticated;
