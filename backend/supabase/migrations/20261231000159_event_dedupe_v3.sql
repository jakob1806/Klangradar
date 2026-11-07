-- Dubletten-Erkennung v3 (Nutzerfeedback 07.11.2026: Mahler 2 / BRSO / Rattle
-- viermal am selben Abend in der Isarphilharmonie).
--  * Wortstämme zählen: "Auferstehung" = "Auferstehungssymphonie".
--  * Gleicher Saal auch bei doppelt angelegter Spielstätte (ähnlicher Name).
--  * Gleiche Uhrzeit (±15 Min.), gleicher Raum, ein gemeinsames Titelwort
--    (z. B. Komponist) -> automatisch zusammenführen.
--  * Gleiche Quelle: auch bei starkem Titelbezug statt nur identischem Titel.
-- Danach sofort einmal auflösen.

create or replace function public.event_dedupe_tokens(p_title text, p_venue_name text default null)
returns text[] language sql immutable as $$
  with norm as (
    select translate(lower(coalesce(p_title, '')),
             'àáâäãåèéêëìíîïòóôöõùúûüýçñœ', 'aaaaaaeeeeiiiiooooouuuuycno') t,
           translate(lower(coalesce(p_venue_name, '')),
             'àáâäãåèéêëìíîïòóôöõùúûüýçñœ', 'aaaaaaeeeeiiiiooooouuuuycno') v
  )
  select coalesce(array_agg(distinct w), '{}')
  from norm, regexp_split_to_table(norm.t, '[^a-z0-9]+') w
  where length(w) >= 4
    and w !~ '^[0-9]+$'
    and w <> all (regexp_split_to_array(norm.v, '[^a-z0-9]+'))
    and w not in (
      'konzert','konzerte','orchester','symphonieorchester','sinfonieorchester','rundfunks','rundfunkorchester',
      'bayerischen','bayerische','bayerisches','munchner','muenchner','munchen','muenchen','wiener','berliner',
      'philharmoniker','philharmonie','kammerorchester','staatsorchester','staatsoper','chor','werke','werken',
      'live','abend','sinfoniekonzert','symphoniekonzert','abonnementkonzert','akademiekonzert','saal','premiere',
      'wiederaufnahme','with','mit','und','dirigiert','dirigent','leitung','von','oper','ballett','konzertant',
      'musik','klassik','festival','reihe','zyklus','matinee','soiree','gala','sonntagskonzert','familienkonzert',
      'akte','akten','aufzugen','aufzuegen','drei','vier','zwei','fuenf','funf','in','the','and','des','der','die',
      'das','dem','den','brso','mphil','sinfonie','symphonie','moll','nr','op','werk','programm','eine','einer','einem','fur','fuer','zum','zur','studierende','studienkonzert')
$$;

create or replace function public.event_duplicate_pairs(p_from timestamptz default now() - interval '1 day')
returns table (a_id uuid, b_id uuid, score numeric, reasons text[], action text)
language sql stable set search_path = public as $$
  with ev as (
    select e.id, e.title, e.source_id, e.venue_id, v.name venue_name, e.start_datetime, e.venue_detail,
           v.slot_exclusive,
           event_dedupe_tokens(e.title, v.name) tokens,
           event_dedupe_title(e.title) ctitle,
           regexp_replace(lower(e.title), '[^[:alnum:]]+', '', 'g') exact_title,
           (select array_agg(coalesce(ep.person_id, ep.ensemble_id)) from event_participants ep
             where ep.event_id = e.id and coalesce(ep.role::text, '') || coalesce(ep.role_label, '') !~* 'moderation|einführung|gast') cast_ids,
           (select array_agg(ew.work_id) from event_works ew where ew.event_id = e.id) work_ids
    from events e
    join venues v on v.id = e.venue_id
    where e.status in ('scheduled', 'sold_out', 'cancelled', 'postponed')
      and e.duplicate_of is null
      and e.start_datetime >= p_from
  ),
  pairs as (
    select a.id a_id, b.id b_id,
      a.source_id is not distinct from b.source_id same_source,
      abs(extract(epoch from b.start_datetime - a.start_datetime)) / 60 dmin,
      (select count(*) from unnest(a.tokens) t where exists (select 1 from unnest(b.tokens) u where u = t or (least(length(t), length(u)) >= 6 and (u like t || '%' or t like u || '%')))) shared,
      least(cardinality(a.tokens), cardinality(b.tokens)) min_tokens,
      similarity(a.ctitle, b.ctitle) csim,
      (length(a.ctitle) >= 5 and length(b.ctitle) >= 5
        and (a.ctitle like '%' || b.ctitle || '%' or b.ctitle like '%' || a.ctitle || '%')) contained,
      a.exact_title = b.exact_title exact,
      coalesce(a.cast_ids && b.cast_ids, false) cast_overlap,
      coalesce(a.work_ids && b.work_ids, false) work_overlap,
      a.slot_exclusive,
      (a.venue_detail is null or b.venue_detail is null) one_room_unknown
    from ev a
    join ev b on a.id < b.id
     and (b.venue_id = a.venue_id
          or similarity(lower(a.venue_name), lower(b.venue_name)) >= 0.6
          or (length(a.venue_name) >= 6 and length(b.venue_name) >= 6
              and (lower(a.venue_name) like '%' || lower(b.venue_name) || '%'
                   or lower(b.venue_name) like '%' || lower(a.venue_name) || '%')))
     and abs(extract(epoch from b.start_datetime - a.start_datetime)) <= 3 * 3600
     and (a.start_datetime at time zone 'Europe/Berlin')::date = (b.start_datetime at time zone 'Europe/Berlin')::date
     -- Verschiedene, bekannte Räume sind nie derselbe Termin.
     and (a.venue_detail is null or b.venue_detail is null or lower(a.venue_detail) = lower(b.venue_detail))
  ),
  scored as (
    select p.*,
      array_remove(array[
        case when dmin <= 15 then 'gleiche Zeit' when dmin <= 180 then 'gleicher Tag, ' || round(dmin) || ' Min. versetzt' end,
        case when exact then 'identischer Titel' when contained then 'Titel enthält den anderen'
             when csim >= 0.5 then 'ähnlicher Titel (' || round(csim::numeric, 2) || ')' end,
        case when shared > 0 then shared || ' gemeinsame Titelwörter' end,
        case when cast_overlap then 'gemeinsame Mitwirkende' end,
        case when work_overlap then 'gemeinsame Werke' end,
        case when slot_exclusive then 'Bühne mit nur einer Vorstellung' end,
        case when same_source then 'gleiche Quelle' end
      ], null) reasons,
      case
        -- Gleiche Quelle: nur bei identischem Titel zur selben Zeit (die Quelle
        -- hat denselben Termin unter zwei Adressen geliefert).
        when same_source then case
          when dmin <= 15 and exact and min_tokens > 0 then 'auto'
          when dmin <= 15 and (shared >= 2 or contained or (cast_overlap and work_overlap)) then 'auto'
          when dmin <= 15 and (shared >= 1 or cast_overlap or work_overlap) then 'review'
        end
        when dmin <= 15 then case
          when shared >= 1 then 'auto'
          when contained then 'auto'
          when shared >= 1 and (csim >= 0.3 or contained or cast_overlap or work_overlap) then 'auto'
          when min_tokens > 0 and (csim >= 0.5 or contained) then 'auto'
          when cast_overlap and work_overlap then 'auto'
          when slot_exclusive and one_room_unknown and (cast_overlap or work_overlap or csim >= 0.2) then 'auto'
          when cast_overlap or work_overlap then 'review'
          when slot_exclusive and one_room_unknown then 'review'
        end
        -- Gleicher Tag, andere Uhrzeit: nie automatisch (könnte eine zweite
        -- Vorstellung sein) – aber als mögliche Zeitänderung prüfen lassen.
        when (shared >= 2 or (min_tokens > 0 and (csim >= 0.75 or contained))) then 'review'
      end action,
      least(1.0,
        case when dmin <= 15 then 0.4 else 0.1 end
        + least(0.3, 0.12 * shared)
        + 0.2 * greatest(csim, case when contained then 0.8 else 0 end)
        + case when cast_overlap then 0.15 else 0 end
        + case when work_overlap then 0.15 else 0 end
        + case when slot_exclusive and dmin <= 15 then 0.1 else 0 end)::numeric(4, 3) score
    from pairs p
  )
  select a_id, b_id, score, reasons, action from scored where action is not null
$$;
revoke all on function public.event_duplicate_pairs(timestamptz) from public, anon;
grant execute on function public.event_duplicate_pairs(timestamptz) to authenticated;

select public.resolve_event_duplicates();
