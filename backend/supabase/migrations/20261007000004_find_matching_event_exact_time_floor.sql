-- Nutzerfeedback ("ich habe das Gefühl, dass es einige Doppelungen in den
-- Konzerten gibt") — Prüfung ergab 16 echte Duplikat-Paare (32 Events),
-- alle mit identischer Venue UND identischer start_datetime, aber so
-- unterschiedlichem Titelwortlaut zwischen zwei Quellen (z.B. "Symphonie-
-- orchester des Bayerischen Rundfunks mit Riccardo Chailly" vs. "Riccardo
-- Chailly: Wolfgang Rihm zu Ehren"; oder "18. Münchner Orgelherbst" als
-- Sammel-Titel bei jedem Termin vs. der jeweils konkrete Solist:innen-
-- Titel), dass weder die reine Trigram-Ähnlichkeit noch der Teilstring-Bonus
-- aus 20261007000001 anschlugen — die RPC lieferte für diese Paare gar
-- keinen Kandidaten zurück (similarity < 0.35), die Events wurden nie in
-- duplicate_candidates geflaggt.
--
-- Fix: Gleiche Venue + exakt identische start_datetime ist für sich schon
-- ein starkes Duplikat-Signal (zwei unterschiedliche Konzerte am selben Ort
-- zur exakt selben Sekunde sind in der Praxis nicht vorgekommen). Hebt die
-- similarity in diesem Fall auf mindestens 0.5 an — über dem
-- Rückgabe-Schwellwert (0.35), damit der Kandidat überhaupt zurückkommt,
-- aber bewusst UNTER dem "sicher genug für Auto-Merge"-Schwellwert (0.7,
-- siehe ingest-source/write.ts), damit ein neues Event bei exakter
-- Zeitübereinstimmung aber abweichendem Titel weiterhin nur als
-- duplicate_candidate geflaggt (Status "pending", manuelle Prüfung im
-- Admin), nicht automatisch gemergt wird — echte Titel-Übereinstimmung
-- (Substring-Bonus 0.9) darf weiterhin auto-mergen.
create or replace function find_matching_event(
  p_title text,
  p_venue_id uuid,
  p_start_datetime timestamptz,
  p_similarity_threshold numeric default 0.35,
  p_result_limit int default 5,
  p_cast_names text[] default null
)
returns table (id uuid, title text, similarity numeric, start_datetime timestamptz)
language sql
stable
as $$
  with candidates as (
    select
      events.id,
      events.title,
      similarity(events.title, p_title) as title_similarity,
      regexp_replace(lower(events.title), '[^[:alnum:]]+', '', 'g') as title_norm,
      events.start_datetime
    from events
    where events.venue_id = p_venue_id
      and events.start_datetime between p_start_datetime - interval '2 hours'
                                     and p_start_datetime + interval '2 hours'
  ),
  scored as (
    select
      c.id,
      c.title,
      c.start_datetime,
      greatest(
        -- Bonus von bis zu 0.15, proportional zur besten Namens-Ähnlichkeit
        -- zwischen einem übergebenen Besetzungsnamen und einer/einem bereits
        -- verknüpften Mitwirkenden (Person oder Ensemble) dieses Kandidaten.
        least(1.0, c.title_similarity + 0.15 * coalesce((
          select max(similarity(pn.name, cn))
          from unnest(coalesce(p_cast_names, '{}'::text[])) as cn
          cross join lateral (
            select p.full_name as name
            from event_participants ep
            join persons p on p.id = ep.person_id
            where ep.event_id = c.id
            union all
            select e.name
            from event_participants ep
            join ensembles e on e.id = ep.ensemble_id
            where ep.event_id = c.id
          ) pn
        ), 0)),
        case
          when length(regexp_replace(lower(p_title), '[^[:alnum:]]+', '', 'g')) >= 6
            and (
              c.title_norm like '%' || regexp_replace(lower(p_title), '[^[:alnum:]]+', '', 'g') || '%'
              or regexp_replace(lower(p_title), '[^[:alnum:]]+', '', 'g') like '%' || c.title_norm || '%'
            )
          then 0.9
          else 0.0
        end,
        -- Neu: gleiche Venue + exakt gleiche start_datetime → mindestens 0.5,
        -- unabhängig vom Titel (siehe Kommentar oben).
        case when c.start_datetime = p_start_datetime then 0.5 else 0.0 end
      ) as similarity
    from candidates c
  )
  select id, title, similarity, start_datetime
  from scored
  where similarity >= p_similarity_threshold
  order by similarity desc
  limit p_result_limit;
$$;
