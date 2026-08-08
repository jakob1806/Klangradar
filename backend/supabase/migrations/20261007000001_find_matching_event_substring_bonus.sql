-- Bugfix (Nutzerfeedback): "Sir Simon Rattle | Beethoven 9" und "Symphonieorchester
-- des Bayerischen Rundfunks: Sir Simon Rattle | Beethoven 9: Werke von Bach und
-- Beethoven" landeten als zwei separate Events (gleiche Venue, gleiche Zeit,
-- eindeutig dasselbe Konzert), ebenso "Le Concert Olympique" und "Kit
-- Armstrong, Klavier & Le Concert Olympique". Live geprüft:
--   similarity('Sir Simon Rattle | Beethoven 9', 'Symphonieorchester ... Beethoven 9: ...') = 0.329
--   similarity('Le Concert Olympique', 'Kit Armstrong, Klavier & Le Concert Olympique') = 0.5
-- Erster Fall lag schon UNTER dem RPC-eigenen Rückgabe-Schwellwert (0.35,
-- Kandidat kam nie zurück), zweiter Fall lag ÜBER dem Schwellwert, aber
-- unter dem in ingest-source/write.ts genutzten "sicher genug"-Schwellwert
-- (0.7). Beides derselbe Grundursache: reine Trigram-Ähnlichkeit bewertet
-- einen KURZEN, in einem LANGEN Titel vollständig enthaltenen Titel
-- systematisch niedrig (viele zusätzliche Trigramme im langen String ohne
-- Gegenstück im kurzen), obwohl inhaltlich eindeutig dasselbe Konzert
-- gemeint ist — ein Aggregator-Feed nennt oft nur den Kurztitel, ein
-- anderer hängt Interpret:in/Orchester als Präfix oder Werkdetails als
-- Suffix an.
--
-- Fix: bei GLEICHER Venue UND innerhalb des ohnehin schon engen
-- Zeitfensters (±2h, siehe unten unverändert) zusätzlich prüfen, ob der
-- normalisierte kürzere Titel als Teilstring im normalisierten längeren
-- Titel enthalten ist — wenn ja, gilt das als starkes Signal (auf 0.9
-- angehoben, klar über beiden bestehenden Schwellwerten). Bewusst NUR
-- innerhalb der schon stark eingrenzenden Venue+Zeit-Kandidatenmenge
-- (typischerweise 0-2 Zeilen) angewendet, nicht DB-weit — dort wäre ein
-- kurzer generischer Titel wie "Klavierabend" in vielen unabhängigen
-- Events enthalten und die Teilstring-Regel würde zu falschen Treffern
-- führen.
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
      -- Grobe Normalisierung für den Teilstring-Vergleich: klein schreiben,
      -- alles außer Buchstaben/Ziffern entfernen. [:alnum:] statt \p{L}/\p{N}
      -- (Postgres' Advanced-Regex-Engine kennt letztere Syntax nicht) —
      -- live geprüft, [:alnum:] behält Umlaute korrekt als Buchstaben.
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
        end
      ) as similarity
    from candidates c
  )
  select id, title, similarity, start_datetime
  from scored
  where similarity >= p_similarity_threshold
  order by similarity desc
  limit p_result_limit;
$$;
