-- Erstellt von Claude Code (Störung 27.10.2026): onboarding_follow_suggestions
-- zählte bei JEDEM Aufruf alle kommenden Auftritte und Follower über sämtliche
-- Personen/Ensembles/Orte und lief zuletzt in den Statement-Timeout (57014,
-- > 8 s). Seit der neuen Onboarding-Startseite und den Journal-Vorschlägen wird
-- sie häufiger aufgerufen; während sie lief, wurden auch einfache Abfragen
-- spürbar langsamer und die Startseite der App lief in Zeitüberschreitungen.
--
-- Jetzt: Zählungen als Materialized Views, alle 30 Minuten aktualisiert. Die
-- Funktion liest nur noch vorberechnete Zahlen; Signatur und Ranking bleiben.

create materialized view if not exists public.entity_upcoming_counts as
with upcoming as (
  select ev.id, ev.venue_id, coalesce(ev.city_id, v.city_id) as city_id
  from public.events ev
  join public.venues v on v.id = ev.venue_id
  where ev.start_datetime > now() and ev.status = 'scheduled'
),
links as (
  select 'person'::text as kind, ep.person_id as entity_id, u.id as event_id, u.city_id
  from public.event_participants ep join upcoming u on u.id = ep.event_id
  where ep.person_id is not null
  union all
  select 'ensemble', ep.ensemble_id, u.id, u.city_id
  from public.event_participants ep join upcoming u on u.id = ep.event_id
  where ep.ensemble_id is not null
  union all
  select 'venue', u.venue_id, u.id, u.city_id from upcoming u
)
select kind, entity_id, city_id, count(distinct event_id)::int as n
from links
group by kind, entity_id, city_id;

create unique index if not exists entity_upcoming_counts_key
  on public.entity_upcoming_counts (kind, entity_id, city_id) nulls not distinct;

create materialized view if not exists public.entity_follower_counts as
select 'person'::text as kind, person_id as entity_id, count(*)::int as n from public.user_favorite_persons group by 2
union all
select 'ensemble', ensemble_id, count(*)::int from public.user_favorite_ensembles group by 2
union all
select 'venue', venue_id, count(*)::int from public.user_favorite_venues group by 2;

create unique index if not exists entity_follower_counts_key
  on public.entity_follower_counts (kind, entity_id);

revoke all on public.entity_upcoming_counts, public.entity_follower_counts from anon, authenticated;

create or replace function public.refresh_entity_popularity()
returns void language plpgsql security definer set search_path = public as $$
begin
  refresh materialized view concurrently public.entity_upcoming_counts;
  refresh materialized view concurrently public.entity_follower_counts;
exception when others then raise warning 'Beliebtheits-Cache nicht aktualisiert: %', sqlerrm;
end; $$;
revoke all on function public.refresh_entity_popularity() from public, anon, authenticated;

select cron.unschedule('entity-popularity-refresh') where exists (select 1 from cron.job where jobname = 'entity-popularity-refresh');
select cron.schedule('entity-popularity-refresh', '*/30 * * * *', $$select public.refresh_entity_popularity();$$);

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
  base as (
    select p.id, p.full_name as label, p.photo_url
    from persons p
    where p_kind = 'person'
    union all
    select en.id, en.name, en.photo_url
    from ensembles en
    where p_kind = 'ensemble'
      and not coalesce(en.is_resolution_placeholder, false)
      and not coalesce(en.is_family_root, false)
    union all
    select v.id, v.name, v.photo_url
    from venues v
    where p_kind = 'venue'
  ),
  event_counts as (
    select c.entity_id,
           sum(c.n) filter (where c.city_id = (select city_id from params)) as in_city,
           sum(c.n) as total
    from entity_upcoming_counts c
    where c.kind = p_kind
    group by c.entity_id
  ),
  follower_counts as (
    select f.entity_id, f.n from entity_follower_counts f where f.kind = p_kind
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

notify pgrst, 'reload schema';
