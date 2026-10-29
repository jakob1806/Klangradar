-- Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Ausbau von Admin- und
-- Veranstalter-Dashboard.
--
-- Admin:      Abo-Verwaltung, Datenlücken-Cockpit, Bekanntheit pflegen,
--             Community-Moderation, Plus-Übersicht.
-- Veranstalter: eigene Abos, Werkeinführungen einreichen, Besetzungsänderung
--             melden, Publikum (nur Summen). Analytics und Ticket-Lücken
--             kommen ohne neue Datenbankfunktionen aus.

-- ===========================================================================
-- 1. Abo-Verwaltung
-- ===========================================================================
-- Der automatische Abgleich (sync-event-subscriptions) legt Abos per upsert
-- auf (organizer, season, code) an und überschreibt dabei Name und Link. Von
-- Redaktion oder Veranstalter bearbeitete Abos sind deshalb "locked": ein
-- Trigger hält ihre Felder fest. Zusammengeführte Abos bleiben als
-- ausgeblendete Zeile mit merged_into bestehen, damit der Abgleich sie nicht
-- neu anlegt; neue Termin-Zuordnungen landen per Trigger beim Ziel-Abo.
alter table public.concert_subscriptions
  add column if not exists image_url text,
  add column if not exists hidden boolean not null default false,
  add column if not exists locked boolean not null default false,
  add column if not exists merged_into uuid references public.concert_subscriptions(id) on delete set null,
  add column if not exists edited_at timestamptz;

create or replace function public.concert_subscriptions_keep_edits()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.locked and coalesce(current_setting('klangradar.subscription_edit', true), '') <> '1' then
    new.name := old.name;
    new.url := old.url;
    new.image_url := old.image_url;
    new.hidden := old.hidden;
    new.merged_into := old.merged_into;
    new.locked := true;
    new.edited_at := old.edited_at;
  end if;
  return new;
end;
$$;
drop trigger if exists concert_subscriptions_keep_edits on public.concert_subscriptions;
create trigger concert_subscriptions_keep_edits before update on public.concert_subscriptions
  for each row execute function public.concert_subscriptions_keep_edits();

create or replace function public.event_concert_subscriptions_follow_merge()
returns trigger language plpgsql set search_path = public as $$
declare
  v_target uuid;
begin
  select merged_into into v_target from concert_subscriptions where id = new.subscription_id;
  if v_target is not null then
    new.subscription_id := v_target;
    if exists (select 1 from event_concert_subscriptions
               where event_id = new.event_id and subscription_id = v_target) then
      return null;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists event_concert_subscriptions_follow_merge on public.event_concert_subscriptions;
create trigger event_concert_subscriptions_follow_merge before insert on public.event_concert_subscriptions
  for each row execute function public.event_concert_subscriptions_follow_merge();

create or replace function public.admin_subscriptions(p_query text default null, p_filter text default 'all')
returns table (
  subscription_id uuid, organizer_name text, code text, name text, season text, url text, image_url text,
  hidden boolean, locked boolean, merged_into uuid, upcoming int, total int, members int,
  next_start timestamptz, fallback_image_url text
)
language sql stable security definer set search_path = public as $$
  with stats as (
    select es.subscription_id,
      count(*) filter (where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out'))::int as upcoming,
      count(*)::int as total,
      min(e.start_datetime) filter (where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')) as next_start,
      (array_agg(e.image_urls[1] order by e.start_datetime) filter (where e.image_urls[1] is not null))[1] as fallback_image_url
    from event_concert_subscriptions es
    join events e on e.id = es.event_id
    group by es.subscription_id
  )
  select s.id, s.organizer_name, s.code, s.name, s.season, s.url, s.image_url,
    s.hidden, s.locked, s.merged_into,
    coalesce(st.upcoming, 0), coalesce(st.total, 0),
    (select count(*)::int from user_concert_subscriptions m where m.subscription_id = s.id),
    st.next_start, st.fallback_image_url
  from concert_subscriptions s
  left join stats st on st.subscription_id = s.id
  where is_admin_or_editor()
    and (nullif(btrim(p_query), '') is null
         or s.name ilike '%' || btrim(p_query) || '%'
         or s.code ilike '%' || btrim(p_query) || '%'
         or s.organizer_name ilike '%' || btrim(p_query) || '%')
    and case coalesce(p_filter, 'all')
          when 'empty' then coalesce(st.upcoming, 0) = 0 and s.merged_into is null
          when 'hidden' then s.hidden
          when 'edited' then s.locked
          else s.merged_into is null
        end
  order by s.organizer_name, s.season desc, s.name
  limit 500;
$$;
revoke all on function public.admin_subscriptions(text, text) from public, anon;
grant execute on function public.admin_subscriptions(text, text) to authenticated;

create or replace function public.admin_update_subscription(
  p_subscription_id uuid, p_name text, p_url text, p_image_url text, p_hidden boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Name fehlt'; end if;
  perform set_config('klangradar.subscription_edit', '1', true);
  update concert_subscriptions
     set name = btrim(p_name),
         url = nullif(btrim(p_url), ''),
         image_url = nullif(btrim(p_image_url), ''),
         hidden = coalesce(p_hidden, false),
         locked = true,
         edited_at = now()
   where id = p_subscription_id;
end;
$$;
revoke all on function public.admin_update_subscription(uuid, text, text, text, boolean) from public, anon;
grant execute on function public.admin_update_subscription(uuid, text, text, text, boolean) to authenticated;

create or replace function public.admin_merge_subscriptions(p_source uuid, p_target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  if p_source = p_target then raise exception 'Quelle und Ziel sind identisch'; end if;
  if exists (select 1 from concert_subscriptions where id = p_target and merged_into is not null) then
    raise exception 'Das Ziel-Abo wurde selbst schon zusammengeführt';
  end if;
  perform set_config('klangradar.subscription_edit', '1', true);
  insert into event_concert_subscriptions(event_id, subscription_id)
    select event_id, p_target from event_concert_subscriptions where subscription_id = p_source
    on conflict do nothing;
  delete from event_concert_subscriptions where subscription_id = p_source;
  insert into user_concert_subscriptions(user_id, subscription_id, created_at)
    select user_id, p_target, created_at from user_concert_subscriptions where subscription_id = p_source
    on conflict do nothing;
  delete from user_concert_subscriptions where subscription_id = p_source;
  -- Abos, die schon in die Quelle zusammengeführt waren, zeigen jetzt aufs Ziel.
  update concert_subscriptions set merged_into = p_target where merged_into = p_source;
  update concert_subscriptions
     set merged_into = p_target, hidden = true, locked = true, edited_at = now()
   where id = p_source;
end;
$$;
revoke all on function public.admin_merge_subscriptions(uuid, uuid) from public, anon;
grant execute on function public.admin_merge_subscriptions(uuid, uuid) to authenticated;

-- App-Funktionen: ausgeblendete/zusammengeführte Abos weglassen, gesetztes
-- Titelbild vor dem Bild des ersten Termins bevorzugen.
create or replace function public.subscriptions_catalog(p_city_id uuid default null)
returns table (
  subscription_id uuid, organizer text, organizer_name text, code text, name text, season text, url text,
  upcoming int, next_start timestamptz, last_start timestamptz, image_url text, venue_name text, is_mine boolean
)
language sql stable security definer set search_path = public as $$
  with upcoming as (
    select es.subscription_id, e.id, e.start_datetime, e.image_urls[1] as image_url, e.city_id, v.name as venue_name
    from event_concert_subscriptions es
    join events e on e.id = es.event_id
    left join venues v on v.id = e.venue_id
    where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')
  ),
  agg as (
    select u.subscription_id,
      count(*)::int as upcoming,
      min(u.start_datetime) as next_start,
      max(u.start_datetime) as last_start,
      (array_agg(u.image_url order by u.start_datetime) filter (where u.image_url is not null))[1] as image_url,
      mode() within group (order by u.venue_name) as venue_name,
      mode() within group (order by u.city_id) as city_id
    from upcoming u
    group by u.subscription_id
  )
  select s.id, s.organizer, s.organizer_name, s.code, s.name, s.season, s.url,
    a.upcoming, a.next_start, a.last_start, coalesce(s.image_url, a.image_url), a.venue_name,
    exists (select 1 from user_concert_subscriptions m where m.subscription_id = s.id and m.user_id = auth.uid())
  from concert_subscriptions s
  join agg a on a.subscription_id = s.id
  where not s.hidden and s.merged_into is null
    and (p_city_id is null or a.city_id = p_city_id or a.city_id is null)
  order by s.organizer_name, s.name;
$$;

create or replace function public.suggested_subscriptions()
returns table (subscription_id uuid, name text, organizer_name text, season text, url text, matched int, total int)
language sql stable security definer set search_path = public as $$
  with mine as (
    select event_id from favorites where user_id = auth.uid()
    union select event_id from event_attendance where user_id = auth.uid() and status = 'planned'
  )
  select s.id, s.name, s.organizer_name, s.season, s.url,
         count(*) filter (where es.event_id in (select event_id from mine))::int,
         count(*)::int
  from concert_subscriptions s
  join event_concert_subscriptions es on es.subscription_id = s.id
  join events e on e.id = es.event_id and e.start_datetime >= now()
  where not s.hidden and s.merged_into is null
    and not exists (select 1 from user_concert_subscriptions u where u.subscription_id = s.id and u.user_id = auth.uid())
  group by s.id
  having count(*) filter (where es.event_id in (select event_id from mine)) >= 3
  order by 6 desc limit 5;
$$;

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
    a.upcoming, a.next_start, a.last_start, coalesce(s.image_url, a.image_url), a.venue_name,
    exists (select 1 from user_concert_subscriptions m where m.subscription_id = s.id and m.user_id = auth.uid())
  from concert_subscriptions s
  join agg a on a.subscription_id = s.id
  where not s.hidden and s.merged_into is null
    and (a.with_ensemble >= 2 or (a.with_ensemble >= 1 and a.with_ensemble * 2 >= a.upcoming))
  order by a.next_start, s.name
  limit 20;
$$;

-- ===========================================================================
-- 2. Datenlücken-Cockpit (kommende Termine)
-- ===========================================================================
create or replace function public.admin_data_gap_coverage(p_days int default 90)
returns jsonb language sql stable security definer set search_path = public as $$
  with upcoming as (
    select e.*
    from events e
    where e.start_datetime >= now()
      and e.start_datetime < now() + make_interval(days => least(greatest(coalesce(p_days, 90), 1), 730))
      and e.status in ('scheduled', 'sold_out')
  )
  select case when not is_admin_or_editor() then null else jsonb_build_object(
    'total', (select count(*) from upcoming),
    'image', (select count(*) from upcoming where coalesce(cardinality(image_urls), 0) > 0),
    'cast', (select count(*) from upcoming u where exists (select 1 from event_participants ep where ep.event_id = u.id)),
    'program', (select count(*) from upcoming u where exists (select 1 from event_works ew where ew.event_id = u.id)),
    'ticket', (select count(*) from upcoming where nullif(btrim(ticket_url), '') is not null),
    'price', (select count(*) from upcoming where price_min is not null or coalesce(is_free, false))
  ) end;
$$;
revoke all on function public.admin_data_gap_coverage(int) from public, anon;
grant execute on function public.admin_data_gap_coverage(int) to authenticated;

create or replace function public.admin_events_with_gap(p_gap text, p_days int default 90, p_limit int default 100)
returns table (
  event_id uuid, title text, start_datetime timestamptz, venue_name text, organizer_name text, saves int
)
language sql stable security definer set search_path = public as $$
  select e.id, e.title, e.start_datetime, v.name, o.name,
    (select count(*)::int from favorites f where f.event_id = e.id)
  from events e
  left join venues v on v.id = e.venue_id
  left join organizers o on o.id = e.organizer_id
  where is_admin_or_editor()
    and e.start_datetime >= now()
    and e.start_datetime < now() + make_interval(days => least(greatest(coalesce(p_days, 90), 1), 730))
    and e.status in ('scheduled', 'sold_out')
    and case p_gap
          when 'image' then coalesce(cardinality(e.image_urls), 0) = 0
          when 'cast' then not exists (select 1 from event_participants ep where ep.event_id = e.id)
          when 'program' then not exists (select 1 from event_works ew where ew.event_id = e.id)
          when 'ticket' then nullif(btrim(e.ticket_url), '') is null
          when 'price' then e.price_min is null and not coalesce(e.is_free, false)
          else false
        end
  -- Wichtigste Lücken zuerst: viel gemerkte und bald stattfindende Termine.
  order by 6 desc, e.start_datetime
  limit least(greatest(coalesce(p_limit, 100), 1), 500);
$$;
revoke all on function public.admin_events_with_gap(text, int, int) from public, anon;
grant execute on function public.admin_events_with_gap(text, int, int) to authenticated;

-- ===========================================================================
-- 3. Bekanntheit pflegen
-- ===========================================================================
-- boost wird zum Wikipedia-Score addiert (−10 = aus den Vorschlägen ohne
-- Suchbegriff ausblenden). Zeilen ohne Wikipedia-Aufrufe (wiki_views = 0)
-- entstehen nur durch manuelle Pflege.
alter table public.entity_prominence
  add column if not exists boost real not null default 0,
  add column if not exists boost_note text,
  add column if not exists boost_updated_at timestamptz;

create or replace function public.admin_prominence_list(p_kind text, p_query text default null, p_limit int default 100)
returns table (
  entity_id uuid, label text, photo_url text, wiki_views bigint, score real, boost real, boost_note text,
  upcoming int, followers int
)
language sql stable security definer set search_path = public as $$
  with base as (
    select p.id, p.full_name as label, p.photo_url from persons p where p_kind = 'person'
    union all
    select en.id, en.name, en.photo_url from ensembles en
      where p_kind = 'ensemble' and not coalesce(en.is_resolution_placeholder, false) and not coalesce(en.is_family_root, false)
    union all
    select v.id, v.name, v.photo_url from venues v where p_kind = 'venue'
  ),
  counts as (
    select c.entity_id, sum(c.n)::int as n from entity_upcoming_counts c where c.kind = p_kind group by c.entity_id
  )
  select b.id, b.label, b.photo_url, coalesce(ep.wiki_views, 0), coalesce(ep.score, 0), coalesce(ep.boost, 0), ep.boost_note,
    coalesce(c.n, 0), coalesce(fc.n, 0)
  from base b
  left join entity_prominence ep on ep.kind = p_kind and ep.entity_id = b.id
  left join counts c on c.entity_id = b.id
  left join entity_follower_counts fc on fc.kind = p_kind and fc.entity_id = b.id
  where is_admin_or_editor()
    and b.label is not null
    and case when nullif(btrim(p_query), '') is null
             then coalesce(c.n, 0) > 0 or coalesce(ep.boost, 0) <> 0
             else b.label ilike '%' || btrim(p_query) || '%' end
  order by least(coalesce(ep.score, 0), 6) + coalesce(ep.boost, 0) + 1.2 * ln(1 + coalesce(c.n, 0)) desc, b.label
  limit least(greatest(coalesce(p_limit, 100), 1), 300);
$$;
revoke all on function public.admin_prominence_list(text, text, int) from public, anon;
grant execute on function public.admin_prominence_list(text, text, int) to authenticated;

create or replace function public.admin_set_prominence_boost(p_kind text, p_entity_id uuid, p_boost real, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  if p_kind not in ('person', 'ensemble', 'venue') then raise exception 'Unbekannte Art'; end if;
  insert into entity_prominence(kind, entity_id, wiki_views, score, boost, boost_note, boost_updated_at)
  values (p_kind, p_entity_id, 0, 0, greatest(least(coalesce(p_boost, 0), 10), -10), nullif(btrim(p_note), ''), now())
  on conflict (kind, entity_id) do update
    set boost = excluded.boost, boost_note = excluded.boost_note, boost_updated_at = now();
end;
$$;
revoke all on function public.admin_set_prominence_boost(text, uuid, real, text) from public, anon;
grant execute on function public.admin_set_prominence_boost(text, uuid, real, text) to authenticated;

-- Onboarding-Vorschläge: unveränderte Gewichtung plus boost; Ensemblemitglieder
-- ohne Wikipedia-Artikel erkennt die Funktion jetzt an wiki_views = 0 statt an
-- einer fehlenden Zeile (manuell gepflegte Einträge haben eine Zeile).
create or replace function public.onboarding_follow_suggestions(p_kind text, p_city_id uuid DEFAULT NULL::uuid, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 60)
 RETURNS TABLE(id uuid, label text, photo_url text, upcoming_in_city integer, upcoming_total integer, followers integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select p.id, p.full_name as label, p.photo_url,
           (coalesce(p.is_deceased, false) or p.death_date is not null or p.birth_date < date '1920-01-01') as deceased,
           (p.member_of_ensemble_id is not null) as ensemble_member
    from persons p
    where p_kind = 'person'
    union all
    select en.id, en.name, en.photo_url, false, false
    from ensembles en
    where p_kind = 'ensemble'
      and not coalesce(en.is_resolution_placeholder, false)
      and not coalesce(en.is_family_root, false)
    union all
    select v.id, v.name, v.photo_url, false, false
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
  ),
  scored as (
    select b.id, b.label, b.photo_url, b.deceased,
           coalesce(ec.in_city, 0)::int as in_city,
           coalesce(ec.total, 0)::int as total,
           coalesce(fc.n, 0)::int as followers,
           coalesce(ep.score, 0) as fame,
           coalesce(ep.boost, 0) as boost,
           least(coalesce(ep.score, 0), 6) + coalesce(ep.boost, 0)
             + 1.2 * ln(1 + coalesce(ec.in_city, 0))
             + 0.35 * ln(1 + coalesce(ec.total, 0))
             + 0.8 * ln(1 + coalesce(fc.n, 0))
             + case when b.photo_url is not null then 0.6 else -1.5 end
             - case when b.ensemble_member and coalesce(ep.wiki_views, 0) = 0 then 1.5 else 0 end
             as rank_score
    from base b
    left join event_counts ec on ec.entity_id = b.id
    left join follower_counts fc on fc.entity_id = b.id
    left join entity_prominence ep on ep.kind = p_kind and ep.entity_id = b.id
    where b.label is not null
  )
  select s.id, s.label, s.photo_url, s.in_city, s.total, s.followers
  from scored s
  cross join params pa
  where case
          when pa.q is null then not s.deceased and s.total > 0 and s.boost > -10
          else s.label ilike '%' || pa.q || '%'
        end
  order by
    case when pa.q is null then 0
         when s.label ilike pa.q || '%' then 0
         when s.label ilike '% ' || pa.q || '%' then 1
         else 2 end,
    s.rank_score desc,
    s.label
  limit (select lim from params);
$function$;
grant execute on function public.onboarding_follow_suggestions(text, uuid, text, int) to anon, authenticated;

-- ===========================================================================
-- 4. Community-Moderation
-- ===========================================================================
alter table public.user_reports
  add column if not exists handled_at timestamptz,
  add column if not exists handled_by uuid references auth.users(id) on delete set null,
  add column if not exists resolution text check (resolution is null or resolution in ('dismissed', 'made_private'));

create or replace function public.admin_user_reports(p_open_only boolean default true)
returns table (
  report_id bigint, created_at timestamptz, reason text, message text,
  reporter_name text, reported_id uuid, reported_name text, reported_bio text, reported_avatar_url text,
  reported_is_public boolean, reports_against int, handled_at timestamptz, resolution text
)
language sql stable security definer set search_path = public as $$
  select r.id, r.created_at, r.reason, r.message,
    rp.display_name, r.reported_id, dp.display_name, dp.bio, dp.avatar_url, coalesce(dp.is_public, false),
    (select count(*)::int from user_reports x where x.reported_id = r.reported_id),
    r.handled_at, r.resolution
  from user_reports r
  left join profiles rp on rp.id = r.reporter_id
  left join profiles dp on dp.id = r.reported_id
  where is_admin_or_editor()
    and (not coalesce(p_open_only, true) or r.handled_at is null)
  order by r.handled_at nulls first, r.created_at desc
  limit 200;
$$;
revoke all on function public.admin_user_reports(boolean) from public, anon;
grant execute on function public.admin_user_reports(boolean) to authenticated;

-- 'dismissed' = Meldung erledigt ohne Eingriff; 'made_private' = Profil auf
-- privat, Bio und Profilbild entfernt (betrifft alle offenen Meldungen zu
-- dieser Person).
create or replace function public.admin_resolve_user_report(p_report_id bigint, p_resolution text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_reported uuid;
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  if p_resolution not in ('dismissed', 'made_private') then raise exception 'Unbekannte Aktion'; end if;
  select reported_id into v_reported from user_reports where id = p_report_id;
  if v_reported is null then raise exception 'Meldung nicht gefunden'; end if;
  if p_resolution = 'made_private' then
    update profiles set is_public = false, bio = null, avatar_url = null where id = v_reported;
    update user_reports set handled_at = now(), handled_by = auth.uid(), resolution = 'made_private'
     where reported_id = v_reported and handled_at is null;
  else
    update user_reports set handled_at = now(), handled_by = auth.uid(), resolution = 'dismissed'
     where id = p_report_id;
  end if;
end;
$$;
revoke all on function public.admin_resolve_user_report(bigint, text) from public, anon;
grant execute on function public.admin_resolve_user_report(bigint, text) to authenticated;

-- Auffällig viele offene Freundschaftsanfragen, v. a. über "Wer war noch da?"
-- (source = 'concert').
create or replace function public.admin_friend_request_activity(p_days int default 7, p_min int default 10)
returns table (user_id uuid, display_name text, sent int, from_concerts int, oldest timestamptz)
language sql stable security definer set search_path = public as $$
  select fr.from_user, p.display_name, count(*)::int,
    count(*) filter (where fr.source = 'concert')::int, min(fr.created_at)
  from friend_requests fr
  left join profiles p on p.id = fr.from_user
  where is_admin_or_editor()
    and fr.created_at >= now() - make_interval(days => least(greatest(coalesce(p_days, 7), 1), 90))
  group by fr.from_user, p.display_name
  having count(*) >= greatest(coalesce(p_min, 10), 1)
  order by 3 desc
  limit 100;
$$;
revoke all on function public.admin_friend_request_activity(int, int) from public, anon;
grant execute on function public.admin_friend_request_activity(int, int) to authenticated;

create or replace function public.admin_withdraw_friend_requests(p_user_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_count int;
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  delete from friend_requests where from_user = p_user_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.admin_withdraw_friend_requests(uuid) from public, anon;
grant execute on function public.admin_withdraw_friend_requests(uuid) to authenticated;

-- ===========================================================================
-- 5. Plus-Übersicht (nur Admins)
-- ===========================================================================
create or replace function public.admin_plus_overview()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not is_admin() then null else jsonb_build_object(
    'active', (select count(*) from plus_entitlements where starts_at <= now() and (expires_at is null or expires_at > now())),
    'active_app_store', (select count(*) from plus_entitlements where source = 'app_store' and starts_at <= now() and (expires_at is null or expires_at > now())),
    'active_code', (select count(*) from plus_entitlements where source = 'code' and starts_at <= now() and (expires_at is null or expires_at > now())),
    'unlimited', (select count(*) from plus_entitlements where expires_at is null),
    'expiring_14d', (select count(*) from plus_entitlements where expires_at > now() and expires_at <= now() + interval '14 days'),
    'expired_30d', (select count(*) from plus_entitlements where expires_at <= now() and expires_at > now() - interval '30 days'),
    'new_30d', (select count(*) from plus_entitlements where starts_at > now() - interval '30 days'),
    'redemptions_30d', (select count(*) from plus_code_redemptions where redeemed_at > now() - interval '30 days')
  ) end;
$$;
revoke all on function public.admin_plus_overview() from public, anon;
grant execute on function public.admin_plus_overview() to authenticated;

create or replace function public.admin_plus_codes()
returns table (
  code text, allowed_email text, duration_days int, max_uses int, uses int, valid_until timestamptz, note text, created_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select c.code, c.allowed_email, (extract(epoch from c.duration) / 86400)::int, c.max_uses, c.uses, c.valid_until, c.note, c.created_at
  from plus_codes c
  where is_admin()
  order by c.created_at desc
  limit 300;
$$;
revoke all on function public.admin_plus_codes() from public, anon;
grant execute on function public.admin_plus_codes() to authenticated;

create or replace function public.admin_create_plus_code(
  p_code text, p_duration_days int, p_max_uses int, p_valid_until timestamptz, p_note text, p_allowed_email text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Keine Berechtigung'; end if;
  if nullif(btrim(p_code), '') is null or btrim(p_code) !~ '^[A-Za-z0-9-]{4,40}$' then
    raise exception 'Code: 4–40 Zeichen, nur Buchstaben, Ziffern und Bindestrich';
  end if;
  insert into plus_codes(code, allowed_email, duration, max_uses, valid_until, note)
  values (upper(btrim(p_code)), nullif(lower(btrim(p_allowed_email)), ''),
          case when coalesce(p_duration_days, 0) > 0 then make_interval(days => p_duration_days) end,
          greatest(coalesce(p_max_uses, 1), 1), p_valid_until, nullif(btrim(p_note), ''));
end;
$$;
revoke all on function public.admin_create_plus_code(text, int, int, timestamptz, text, text) from public, anon;
grant execute on function public.admin_create_plus_code(text, int, int, timestamptz, text, text) to authenticated;

-- ===========================================================================
-- 6. Veranstalter: eigene Abos
-- ===========================================================================
-- Ein Abo gehört zum Veranstalter, wenn mindestens ein Termin des Abos zu
-- einem Veranstalterkontext gehört, für den der Nutzer Termine bearbeiten darf.
create or replace function public.can_edit_concert_subscription(p_subscription_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from event_concert_subscriptions es
    join events e on e.id = es.event_id
    where es.subscription_id = p_subscription_id
      and e.organizer_id is not null
      and has_organizer_capability(e.organizer_id, 'events')
  );
$$;
revoke all on function public.can_edit_concert_subscription(uuid) from public, anon;
grant execute on function public.can_edit_concert_subscription(uuid) to authenticated;

create or replace function public.organizer_subscriptions()
returns table (
  subscription_id uuid, organizer_name text, code text, name text, season text, url text,
  upcoming int, total int, members int, next_start timestamptz, edited_at timestamptz
)
language sql stable security definer set search_path = public as $$
  with mine as (
    select distinct es.subscription_id
    from event_concert_subscriptions es
    join events e on e.id = es.event_id
    where e.organizer_id in (
      select distinct e2.organizer_id from events e2
      where e2.organizer_id is not null and has_organizer_capability(e2.organizer_id, 'events')
    )
  )
  select s.id, s.organizer_name, s.code, s.name, s.season, s.url,
    (select count(*)::int from event_concert_subscriptions es join events e on e.id = es.event_id
      where es.subscription_id = s.id and e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')),
    (select count(*)::int from event_concert_subscriptions es where es.subscription_id = s.id),
    -- Nur die Summe, keine Nutzerdaten.
    (select count(*)::int from user_concert_subscriptions m where m.subscription_id = s.id),
    (select min(e.start_datetime) from event_concert_subscriptions es join events e on e.id = es.event_id
      where es.subscription_id = s.id and e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')),
    s.edited_at
  from concert_subscriptions s
  join mine m on m.subscription_id = s.id
  where not s.hidden and s.merged_into is null
  order by s.season desc, s.name;
$$;
revoke all on function public.organizer_subscriptions() from public, anon;
grant execute on function public.organizer_subscriptions() to authenticated;

create or replace function public.organizer_update_subscription(p_subscription_id uuid, p_name text, p_url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_edit_concert_subscription(p_subscription_id) then raise exception 'Keine Berechtigung'; end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Name fehlt'; end if;
  if nullif(btrim(p_url), '') is not null and btrim(p_url) !~* '^https?://' then
    raise exception 'Der Link muss mit http:// oder https:// beginnen';
  end if;
  perform set_config('klangradar.subscription_edit', '1', true);
  update concert_subscriptions
     set name = btrim(p_name), url = nullif(btrim(p_url), ''), locked = true, edited_at = now()
   where id = p_subscription_id;
end;
$$;
revoke all on function public.organizer_update_subscription(uuid, text, text) from public, anon;
grant execute on function public.organizer_update_subscription(uuid, text, text) to authenticated;

-- Termine zu- oder abordnen (nur eigene Termine).
create or replace function public.organizer_set_subscription_event(p_subscription_id uuid, p_event_id uuid, p_linked boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_edit_concert_subscription(p_subscription_id)
     or not exists (select 1 from events e where e.id = p_event_id and e.organizer_id is not null
                    and has_organizer_capability(e.organizer_id, 'events')) then
    raise exception 'Keine Berechtigung';
  end if;
  if p_linked then
    insert into event_concert_subscriptions(event_id, subscription_id) values (p_event_id, p_subscription_id)
    on conflict do nothing;
  else
    delete from event_concert_subscriptions where event_id = p_event_id and subscription_id = p_subscription_id;
  end if;
  -- Der automatische Abgleich soll die Zuordnung dieses Termins nicht wieder umwerfen.
  update events set subscriptions_synced_at = now() where id = p_event_id;
  perform set_config('klangradar.subscription_edit', '1', true);
  update concert_subscriptions set locked = true, edited_at = now() where id = p_subscription_id;
end;
$$;
revoke all on function public.organizer_set_subscription_event(uuid, uuid, boolean) from public, anon;
grant execute on function public.organizer_set_subscription_event(uuid, uuid, boolean) to authenticated;

-- ===========================================================================
-- 7. Veranstalter: Werkeinführungen einreichen (Redaktion gibt frei)
-- ===========================================================================
create table if not exists public.work_introduction_submissions (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references public.works(id) on delete cascade,
  organizer_id uuid references public.organizers(id) on delete set null,
  submitted_by uuid not null references auth.users(id) on delete cascade,
  text text not null check (char_length(text) between 80 and 4000),
  source_url text,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);
create index if not exists work_introduction_submissions_pending_idx
  on public.work_introduction_submissions(created_at) where status = 'pending';
alter table public.work_introduction_submissions enable row level security;
create policy "Eigene Einreichungen lesen" on public.work_introduction_submissions
  for select using (submitted_by = auth.uid() or is_admin_or_editor());
grant select on public.work_introduction_submissions to authenticated;

create or replace function public.organizer_program_works()
returns table (
  work_id uuid, title text, catalog_number text, composer_name text, concerts int, next_start timestamptz,
  introduction_de text, introduction_source text, pending boolean, organizer_id uuid
)
language sql stable security definer set search_path = public as $$
  with own as (
    select ew.work_id, e.id as event_id, e.start_datetime, e.organizer_id
    from event_works ew
    join events e on e.id = ew.event_id
    where e.start_datetime >= now() and e.status in ('scheduled', 'sold_out')
      and e.organizer_id is not null
      and has_organizer_capability(e.organizer_id, 'events')
  ),
  agg as (
    select o.work_id, count(distinct o.event_id)::int as concerts, min(o.start_datetime) as next_start,
      (array_agg(o.organizer_id order by o.start_datetime))[1] as organizer_id
    from own o group by o.work_id
  )
  select w.id, w.title, w.catalog_number, p.full_name, a.concerts, a.next_start,
    w.introduction_de, w.introduction_source,
    exists (select 1 from work_introduction_submissions s
            where s.work_id = w.id and s.status = 'pending' and s.submitted_by = auth.uid()),
    a.organizer_id
  from agg a
  join works w on w.id = a.work_id
  left join persons p on p.id = w.composer_id
  order by (w.introduction_de is null) desc, a.next_start
  limit 400;
$$;
revoke all on function public.organizer_program_works() from public, anon;
grant execute on function public.organizer_program_works() to authenticated;

create or replace function public.organizer_submit_work_introduction(p_work_id uuid, p_text text, p_source_url text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_organizer uuid;
begin
  select e.organizer_id into v_organizer
  from event_works ew join events e on e.id = ew.event_id
  where ew.work_id = p_work_id and e.organizer_id is not null and has_organizer_capability(e.organizer_id, 'events')
  order by e.start_datetime desc limit 1;
  if v_organizer is null then raise exception 'Das Werk steht in keinem eurer Programme'; end if;
  if char_length(btrim(coalesce(p_text, ''))) < 80 then raise exception 'Bitte mindestens 80 Zeichen schreiben'; end if;
  if nullif(btrim(p_source_url), '') is not null and btrim(p_source_url) !~* '^https?://' then
    raise exception 'Der Link muss mit http:// oder https:// beginnen';
  end if;
  -- Eine offene Einreichung pro Person und Werk: neue ersetzt die alte.
  delete from work_introduction_submissions
   where work_id = p_work_id and submitted_by = auth.uid() and status = 'pending';
  insert into work_introduction_submissions(work_id, organizer_id, submitted_by, text, source_url)
  values (p_work_id, v_organizer, auth.uid(), left(btrim(p_text), 4000), nullif(btrim(p_source_url), ''));
end;
$$;
revoke all on function public.organizer_submit_work_introduction(uuid, text, text) from public, anon;
grant execute on function public.organizer_submit_work_introduction(uuid, text, text) to authenticated;

create or replace function public.admin_work_intro_submissions()
returns table (
  submission_id uuid, work_id uuid, work_title text, composer_name text, organizer_name text,
  text text, source_url text, current_intro text, created_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select s.id, w.id, w.title, p.full_name, o.name, s.text, s.source_url, w.introduction_de, s.created_at
  from work_introduction_submissions s
  join works w on w.id = s.work_id
  left join persons p on p.id = w.composer_id
  left join organizers o on o.id = s.organizer_id
  where is_admin_or_editor() and s.status = 'pending'
  order by s.created_at
  limit 100;
$$;
revoke all on function public.admin_work_intro_submissions() from public, anon;
grant execute on function public.admin_work_intro_submissions() to authenticated;

-- Übernommene Texte gelten als Redaktionstext (geprüft) und werden von der
-- automatischen Recherche nie überschrieben.
create or replace function public.admin_review_work_intro_submission(p_submission_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_row work_introduction_submissions;
begin
  if not is_admin_or_editor() then raise exception 'Keine Berechtigung'; end if;
  select * into v_row from work_introduction_submissions where id = p_submission_id and status = 'pending';
  if v_row.id is null then raise exception 'Einreichung nicht gefunden'; end if;
  if p_accept then
    update works
       set introduction_de = v_row.text,
           introduction_source = 'redaktion',
           introduction_source_url = v_row.source_url,
           introduction_checked_at = now()
     where id = v_row.work_id;
  end if;
  update work_introduction_submissions
     set status = case when p_accept then 'accepted' else 'rejected' end, reviewed_at = now(), reviewed_by = auth.uid()
   where id = p_submission_id;
end;
$$;
revoke all on function public.admin_review_work_intro_submission(uuid, boolean) from public, anon;
grant execute on function public.admin_review_work_intro_submission(uuid, boolean) to authenticated;

-- ===========================================================================
-- 8. Veranstalter: Besetzungsänderung melden
-- ===========================================================================
-- Schreibt wie detect_cast_changes() eine event_changes-Zeile (field_name
-- 'cast'); notify-changes schickt daraus den Push an alle, die den Termin
-- gemerkt haben. Höchstens drei Meldungen pro Termin und Tag.
create or replace function public.organizer_report_cast_change(p_event_id uuid, p_removed text, p_added text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event events;
begin
  select * into v_event from events where id = p_event_id;
  if v_event.id is null then raise exception 'Termin nicht gefunden'; end if;
  if not (
    (v_event.organizer_id is not null and has_organizer_capability(v_event.organizer_id, 'events'))
    or has_claimed_profile_event_edit_access(p_event_id)
  ) then
    raise exception 'Keine Berechtigung';
  end if;
  if v_event.start_datetime < now() then raise exception 'Der Termin liegt in der Vergangenheit'; end if;
  if nullif(btrim(p_removed), '') is null and nullif(btrim(p_added), '') is null then
    raise exception 'Bitte angeben, wer neu dabei ist oder wer fehlt';
  end if;
  if (select count(*) from event_changes where event_id = p_event_id and field_name = 'cast'
        and changed_at > now() - interval '1 day') >= 3 then
    raise exception 'Für diesen Termin wurden heute schon drei Änderungen gemeldet';
  end if;
  insert into event_changes(event_id, field_name, old_value, new_value)
  values (p_event_id, 'cast', nullif(left(btrim(p_removed), 200), ''), nullif(left(btrim(p_added), 200), ''));
end;
$$;
revoke all on function public.organizer_report_cast_change(uuid, text, text) from public, anon;
grant execute on function public.organizer_report_cast_change(uuid, text, text) to authenticated;

create or replace function public.organizer_cast_changes(p_event_id uuid)
returns table (changed_at timestamptz, removed text, added text)
language sql stable security definer set search_path = public as $$
  select c.changed_at, c.old_value, c.new_value
  from event_changes c
  join events e on e.id = c.event_id
  where c.event_id = p_event_id and c.field_name = 'cast'
    and ((e.organizer_id is not null and has_organizer_capability(e.organizer_id, 'events'))
         or has_claimed_profile_event_edit_access(p_event_id))
  order by c.changed_at desc
  limit 20;
$$;
revoke all on function public.organizer_cast_changes(uuid) from public, anon;
grant execute on function public.organizer_cast_changes(uuid) to authenticated;

-- ===========================================================================
-- 9. Veranstalter: Publikum (nur Summen)
-- ===========================================================================
-- Die Favoriten-Tabellen haben kein Anlegedatum, deshalb täglicher
-- Schnappschuss der Follower-Zahlen; die Entwicklung baut sich ab heute auf.
create table if not exists public.entity_follower_daily (
  kind text not null check (kind in ('person', 'ensemble', 'venue')),
  entity_id uuid not null,
  day date not null,
  n int not null,
  primary key (kind, entity_id, day)
);
alter table public.entity_follower_daily enable row level security;
revoke all on public.entity_follower_daily from anon, authenticated;

create or replace function public.snapshot_entity_followers()
returns void language sql security definer set search_path = public as $$
  insert into entity_follower_daily(kind, entity_id, day, n)
  select kind, entity_id, (now() at time zone 'Europe/Berlin')::date, n from entity_follower_counts
  on conflict (kind, entity_id, day) do update set n = excluded.n;
$$;
revoke all on function public.snapshot_entity_followers() from public, anon, authenticated;
select public.snapshot_entity_followers();
select cron.unschedule(jobid) from cron.job where jobname = 'snapshot-entity-followers';
select cron.schedule('snapshot-entity-followers', '15 2 * * *', $$ select snapshot_entity_followers(); $$);

create or replace function public.organizer_audience()
returns table (kind text, entity_id uuid, name text, followers int, change_7d int, change_30d int, series jsonb)
language sql stable security definer set search_path = public as $$
  with mine as (
    select distinct c.entity_type as kind, c.entity_id
    from entity_claims c
    where c.user_id = auth.uid() and c.status = 'approved' and c.entity_type in ('person', 'ensemble', 'venue')
  ),
  named as (
    select m.kind, m.entity_id,
      coalesce(p.full_name, en.name, v.name) as name
    from mine m
    left join persons p on m.kind = 'person' and p.id = m.entity_id
    left join ensembles en on m.kind = 'ensemble' and en.id = m.entity_id
    left join venues v on m.kind = 'venue' and v.id = m.entity_id
  )
  select n.kind, n.entity_id, n.name,
    coalesce(fc.n, 0),
    coalesce(fc.n, 0) - (select d.n from entity_follower_daily d where d.kind = n.kind and d.entity_id = n.entity_id
                          and d.day <= current_date - 7 order by d.day desc limit 1),
    coalesce(fc.n, 0) - (select d.n from entity_follower_daily d where d.kind = n.kind and d.entity_id = n.entity_id
                          and d.day <= current_date - 30 order by d.day desc limit 1),
    coalesce((select jsonb_agg(jsonb_build_object('day', d.day, 'n', d.n) order by d.day)
              from entity_follower_daily d
              where d.kind = n.kind and d.entity_id = n.entity_id and d.day > current_date - 90), '[]'::jsonb)
  from named n
  left join entity_follower_counts fc on fc.kind = n.kind and fc.entity_id = n.entity_id
  order by 4 desc;
$$;
revoke all on function public.organizer_audience() from public, anon;
grant execute on function public.organizer_audience() to authenticated;

notify pgrst, 'reload schema';
