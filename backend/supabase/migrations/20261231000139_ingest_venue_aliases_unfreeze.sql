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
