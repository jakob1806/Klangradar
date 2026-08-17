-- Ort und Uhrzeit sind Eingrenzungen, aber kein hinreichender Beweis fuer
-- ein Event-Duplikat: grosse Spielstaetten haben parallele Saele, Opernhaeuser
-- koennen Fuehrungen/Workshops und Vorstellungen gleichzeitig anbieten.

create or replace function public.find_matching_event(
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
      e.id,
      e.title,
      similarity(e.title, p_title) as title_similarity,
      regexp_replace(lower(e.title), '[^[:alnum:]]+', '', 'g') as title_norm,
      e.start_datetime,
      coalesce((
        select max(similarity(linked.name, incoming_name))
        from unnest(coalesce(p_cast_names, '{}'::text[])) incoming_name
        cross join lateral (
          select p.full_name as name
          from event_participants ep join persons p on p.id=ep.person_id
          where ep.event_id=e.id
          union all
          select en.name
          from event_participants ep join ensembles en on en.id=ep.ensemble_id
          where ep.event_id=e.id
        ) linked
      ), 0) as cast_similarity
    from events e
    where e.venue_id=p_venue_id
      and e.start_datetime between p_start_datetime-interval '2 hours'
                                    and p_start_datetime+interval '2 hours'
  ), scored as (
    select c.*,
      greatest(
        least(1.0, c.title_similarity + 0.15*c.cast_similarity),
        case when length(regexp_replace(lower(p_title), '[^[:alnum:]]+', '', 'g'))>=6
          and (c.title_norm like '%' || regexp_replace(lower(p_title), '[^[:alnum:]]+', '', 'g') || '%'
            or regexp_replace(lower(p_title), '[^[:alnum:]]+', '', 'g') like '%' || c.title_norm || '%')
          then 0.9 else 0 end,
        -- Exakte Zeit zaehlt nur zusammen mit wenigstens einem schwachen
        -- Titelsignal oder einer klar uebereinstimmenden Besetzung.
        case when c.start_datetime=p_start_datetime
          and (c.title_similarity>=0.2 or c.cast_similarity>=0.65)
          then 0.5 else 0 end
      ) as match_score
    from candidates c
  )
  select id,title,match_score,start_datetime from scored
  where match_score>=p_similarity_threshold
  order by match_score desc
  limit p_result_limit;
$$;

-- Die vier aktuell offenen, fachlich eindeutig unterschiedlichen Paare aus
-- der Meldung werden nicht geloescht, sondern nachvollziehbar als geprueft
-- und unterschiedlich markiert.
update duplicate_candidates dc
set status='dismissed', reviewed_at=now()
from events a, events b
where dc.status='pending'
  and a.id=dc.event_a_id and b.id=dc.event_b_id
  and (
    (lower(a.title)='crypt_' and lower(b.title)='crypt: tactile tour')
    or (lower(b.title)='crypt_' and lower(a.title)='crypt: tactile tour')
    or (lower(a.title)='bel canto me' and lower(b.title) in ('die lustige witwe','die zauberflöte'))
    or (lower(b.title)='bel canto me' and lower(a.title) in ('die lustige witwe','die zauberflöte'))
    or (lower(a.title)='workshop »aschenbrödel«' and lower(b.title)='workshop »als hitler das rosa kaninchen stahl«')
    or (lower(b.title)='workshop »aschenbrödel«' and lower(a.title)='workshop »als hitler das rosa kaninchen stahl«')
  );
