-- Dubletten schon beim Import verhindern (Nutzerfeedback 07.11.2026:
-- Concerti, BR, Staatsoper und andere Portale liefern dieselben Konzerte,
-- die bisher ungeprüft neu angelegt und erst später aufgeräumt wurden).
-- ingest-source fragt vor jedem neuen Termin find_import_duplicate(); bei
-- einem Treffer wird der bestehende Termin ergänzt statt ein neuer angelegt.
-- Regeln wie event_duplicate_pairs() v3 (Migration 159):
--  * gleicher Kalendertag, Beginn ±15 Minuten
--  * gleiche Spielstätte oder gleich/ähnlich benannte (doppelt angelegte)
--  * mindestens ein gemeinsames Titelwort (auch Wortstamm), Titel enthält
--    den anderen, oder gemeinsame Mitwirkende

create or replace function public.find_import_duplicate(
  p_title text,
  p_venue_id uuid,
  p_start_datetime timestamptz,
  p_cast_names text[] default null
)
returns uuid
language sql stable security definer set search_path = public as $$
  with me as (
    select v.name venue_name,
           event_dedupe_tokens(p_title, v.name) tokens,
           event_dedupe_title(p_title) ctitle
    from venues v where v.id = p_venue_id
  ),
  cand as (
    select e.id, e.start_datetime, e.source_id,
           event_dedupe_tokens(e.title, v.name) tokens,
           event_dedupe_title(e.title) ctitle,
           (p_cast_names is not null and exists (
              select 1 from event_participants ep
              left join persons p on p.id = ep.person_id
              left join ensembles en on en.id = ep.ensemble_id
              where ep.event_id = e.id
                and lower(coalesce(p.full_name, en.name)) = any (select lower(n) from unnest(p_cast_names) n)
           )) cast_overlap
    from events e
    join venues v on v.id = e.venue_id, me
    where e.duplicate_of is null
      and e.status in ('scheduled', 'sold_out', 'cancelled', 'postponed')
      and e.start_datetime between p_start_datetime - interval '15 minutes' and p_start_datetime + interval '15 minutes'
      and (e.venue_id = p_venue_id
           or similarity(lower(v.name), lower(me.venue_name)) >= 0.6
           or (length(v.name) >= 6 and length(me.venue_name) >= 6
               and (lower(v.name) like '%' || lower(me.venue_name) || '%'
                    or lower(me.venue_name) like '%' || lower(v.name) || '%')))
  )
  select c.id
  from cand c, me
  where c.cast_overlap
     or (length(c.ctitle) >= 5 and length(me.ctitle) >= 5
         and (c.ctitle like '%' || me.ctitle || '%' or me.ctitle like '%' || c.ctitle || '%'))
     or exists (
          select 1 from unnest(me.tokens) t
          where exists (select 1 from unnest(c.tokens) u
                        where u = t or (least(length(t), length(u)) >= 6 and (u like t || '%' or t like u || '%'))))
  order by c.cast_overlap desc, abs(extract(epoch from c.start_datetime - p_start_datetime))
  limit 1
$$;
revoke all on function public.find_import_duplicate(text, uuid, timestamptz, text[]) from public, anon, authenticated;
grant execute on function public.find_import_duplicate(text, uuid, timestamptz, text[]) to service_role;
