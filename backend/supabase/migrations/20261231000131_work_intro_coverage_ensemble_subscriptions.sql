-- Erstellt von Claude Code (Nutzerwunsch 29.10.2026):
--
-- 1. Werkeinführungen: Die Recherche (Edge Function work-introduction) gleicht
--    jetzt zusätzlich über Wikidata ab (Werke der Komponist:in mit
--    Werkverzeichnis-/Opusnummer → verlinkter Artikel). Alle Werke ohne
--    Einführung werden deshalb erneut geprüft; der Cron-Job
--    "work-introductions" arbeitet sie alle 5 Minuten ab (kommende Konzerte
--    zuerst). Redaktionstexte bleiben unberührt.
-- 2. Admin-Dashboard "Werkeinführungen": Abdeckung und fehlende Werke,
--    sortiert nach Anzahl kommender Konzerte.
-- 3. Abos je Ensemble (Ensembleseite in der App): Abos, in denen das Ensemble
--    in mindestens zwei kommenden Terminen bzw. der Hälfte der Termine spielt.

update public.works
set introduction_checked_at = null
where introduction_de is null
  and coalesce(introduction_source, '') <> 'redaktion';

create or replace function public.admin_work_introduction_coverage()
returns jsonb
language sql stable security definer set search_path = public as $$
  with upcoming as (
    select ew.work_id, count(distinct e.id) as concerts, min(e.start_datetime) as next_start
    from event_works ew
    join events e on e.id = ew.event_id
    where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')
    group by ew.work_id
  )
  select case when not is_admin_or_editor() then null else jsonb_build_object(
    'total', (select count(*) from works),
    'with_intro', (select count(*) from works where introduction_de is not null),
    'redaktion', (select count(*) from works where introduction_source = 'redaktion'),
    'pending', (select count(*) from works where introduction_checked_at is null),
    'upcoming', (select count(*) from upcoming),
    'upcoming_with_intro', (select count(*) from upcoming u join works w on w.id = u.work_id where w.introduction_de is not null),
    'next30', (select count(*) from upcoming where next_start < now() + interval '30 days'),
    'next30_with_intro', (select count(*) from upcoming u join works w on w.id = u.work_id
                          where u.next_start < now() + interval '30 days' and w.introduction_de is not null)
  ) end;
$$;
revoke all on function public.admin_work_introduction_coverage() from public, anon;
grant execute on function public.admin_work_introduction_coverage() to authenticated;

create or replace function public.admin_works_missing_introduction(p_limit int default 100, p_query text default null)
returns table (
  work_id uuid, title text, catalog_number text, composer_name text,
  concerts int, next_start timestamptz, checked_at timestamptz
)
language sql stable security definer set search_path = public as $$
  with upcoming as (
    select ew.work_id, count(distinct e.id)::int as concerts, min(e.start_datetime) as next_start
    from event_works ew
    join events e on e.id = ew.event_id
    where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')
    group by ew.work_id
  )
  select w.id, w.title, w.catalog_number, p.full_name, u.concerts, u.next_start, w.introduction_checked_at
  from upcoming u
  join works w on w.id = u.work_id
  left join persons p on p.id = w.composer_id
  where is_admin_or_editor()
    and w.introduction_de is null
    and (p_query is null or p_query = '' or w.title ilike '%' || p_query || '%' or p.full_name ilike '%' || p_query || '%')
  order by u.concerts desc, u.next_start
  limit least(greatest(coalesce(p_limit, 100), 1), 500);
$$;
revoke all on function public.admin_works_missing_introduction(int, text) from public, anon;
grant execute on function public.admin_works_missing_introduction(int, text) to authenticated;

create or replace function public.ensemble_subscriptions(p_ensemble_id uuid)
returns table (
  subscription_id uuid, organizer text, organizer_name text, code text, name text, season text, url text,
  upcoming int, next_start timestamptz, last_start timestamptz, image_url text, venue_name text, is_mine boolean
)
language sql stable security definer set search_path = public as $$
  with upcoming as (
    select es.subscription_id, e.id, e.start_datetime, e.image_urls[1] as image_url, v.name as venue_name,
      exists (select 1 from event_participants ep where ep.event_id = e.id and ep.ensemble_id = p_ensemble_id) as with_ensemble
    from event_concert_subscriptions es
    join events e on e.id = es.event_id
    left join venues v on v.id = e.venue_id
    where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')
  ),
  agg as (
    select u.subscription_id,
      count(*)::int as upcoming,
      count(*) filter (where u.with_ensemble)::int as with_ensemble,
      min(u.start_datetime) as next_start,
      max(u.start_datetime) as last_start,
      (array_agg(u.image_url order by u.start_datetime) filter (where u.image_url is not null))[1] as image_url,
      mode() within group (order by u.venue_name) as venue_name
    from upcoming u
    group by u.subscription_id
  )
  select s.id, s.organizer, s.organizer_name, s.code, s.name, s.season, s.url,
    a.upcoming, a.next_start, a.last_start, a.image_url, a.venue_name,
    exists (select 1 from user_concert_subscriptions m where m.subscription_id = s.id and m.user_id = auth.uid())
  from concert_subscriptions s
  join agg a on a.subscription_id = s.id
  where a.with_ensemble >= 2 or (a.with_ensemble >= 1 and a.with_ensemble * 2 >= a.upcoming)
  order by a.next_start, s.name
  limit 20;
$$;
revoke all on function public.ensemble_subscriptions(uuid) from public;
grant execute on function public.ensemble_subscriptions(uuid) to anon, authenticated;
