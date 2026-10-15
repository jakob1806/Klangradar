-- Erstellt mit Claude Code.
--
-- Onboarding "Wem möchtest du folgen?": bisher lud jeder der drei Schritte
-- die KOMPLETTE Tabelle (persons: >3.000 Zeilen in 7 nacheinander
-- abgesetzten 500er-Seiten) und sortierte im Client alphabetisch. Folge:
-- langsamer Schritt, gelegentliches Hängen, und oben standen beliebige
-- Namen mit "A" statt der relevanten Künstler:innen.
--
-- Diese Funktion liefert pro Kategorie nur eine kleine, gerankte Liste:
--   ohne p_query: die "Top" — meiste kommende Konzerte in der Stadt des
--     Nutzers, dann insgesamt, dann Follower, dann mit Foto, dann Name;
--   mit p_query: Treffer zum Suchbegriff (Namensanfang zuerst), ebenfalls
--     nach Relevanz sortiert — für die kompakte Suchliste.
-- p_city_id fällt auf profiles.active_city_id des angemeldeten Nutzers
-- zurück (im Onboarding direkt im Schritt davor gewählt).
--
-- security definer, weil Follower-Zahlen über user_favorite_* aggregiert
-- werden (per RLS sonst nur die eigenen sichtbar); zurückgegeben werden
-- ausschließlich öffentliche Stammdaten plus anonyme Zählwerte.

create or replace function public.onboarding_follow_suggestions(
  p_kind text,
  p_city_id uuid default null,
  p_query text default null,
  p_limit int default 60
)
returns table (
  id uuid,
  label text,
  photo_url text,
  upcoming_in_city int,
  upcoming_total int,
  followers int
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      coalesce(
        p_city_id,
        (select pr.active_city_id from profiles pr where pr.id = auth.uid())
      ) as city_id,
      nullif(btrim(p_query), '') as q,
      least(greatest(coalesce(p_limit, 60), 1), 200) as lim
  ),
  upcoming as (
    select ev.id, ev.venue_id, coalesce(ev.city_id, v.city_id) as city_id
    from events ev
    join venues v on v.id = ev.venue_id
    where ev.start_datetime > now()
      and ev.status = 'scheduled'
  ),
  base as (
    select p.id, p.full_name as label, p.photo_url
    from persons p
    where p_kind = 'person'
    union all
    select en.id, en.name, en.photo_url
    from ensembles en
    where p_kind = 'ensemble'
      -- wie ensembleOptionsProvider: technische Platzhalter/Familien-Wurzeln
      -- sind keine echten Ensembles zum Folgen.
      and not coalesce(en.is_resolution_placeholder, false)
      and not coalesce(en.is_family_root, false)
    union all
    select v.id, v.name, v.photo_url
    from venues v
    where p_kind = 'venue'
  ),
  event_counts as (
    select x.entity_id,
           count(distinct x.event_id) filter (where x.city_id = (select city_id from params)) as in_city,
           count(distinct x.event_id) as total
    from (
      select ep.person_id as entity_id, u.id as event_id, u.city_id
      from event_participants ep join upcoming u on u.id = ep.event_id
      where p_kind = 'person' and ep.person_id is not null
      union all
      select ep.ensemble_id, u.id, u.city_id
      from event_participants ep join upcoming u on u.id = ep.event_id
      where p_kind = 'ensemble' and ep.ensemble_id is not null
      union all
      select u.venue_id, u.id, u.city_id
      from upcoming u
      where p_kind = 'venue'
    ) x
    group by x.entity_id
  ),
  follower_counts as (
    select person_id as entity_id, count(*) as n from user_favorite_persons where p_kind = 'person' group by 1
    union all
    select ensemble_id, count(*) from user_favorite_ensembles where p_kind = 'ensemble' group by 1
    union all
    select venue_id, count(*) from user_favorite_venues where p_kind = 'venue' group by 1
  )
  select b.id,
         b.label,
         b.photo_url,
         coalesce(ec.in_city, 0)::int,
         coalesce(ec.total, 0)::int,
         coalesce(fc.n, 0)::int
  from base b
  cross join params pa
  left join event_counts ec on ec.entity_id = b.id
  left join follower_counts fc on fc.entity_id = b.id
  where b.label is not null
    and (pa.q is null or b.label ilike '%' || pa.q || '%')
  order by
    -- Bei Suche: Namensanfang bzw. Wortanfang vor Treffern mitten im Namen.
    case when pa.q is null then 0
         when b.label ilike pa.q || '%' then 0
         when b.label ilike '% ' || pa.q || '%' then 1
         else 2 end,
    coalesce(ec.in_city, 0) desc,
    coalesce(ec.total, 0) desc,
    coalesce(fc.n, 0) desc,
    (b.photo_url is not null) desc,
    b.label
  limit (select lim from params);
$$;

grant execute on function public.onboarding_follow_suggestions(text, uuid, text, int) to anon, authenticated;
