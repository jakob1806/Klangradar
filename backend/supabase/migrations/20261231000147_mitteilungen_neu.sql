-- Erstellt von Claude Code (Nutzerentscheidung 01.11.2026 zum Konzept
-- docs/14-mitteilungen-konzept.md): "Wichtiges kann sofort kommen, Planung
-- genau eine pro Konzert, höchstens etwa 10 pro Woche, man kann aber mehr
-- auswählen bzw. mehr Kategorien; Einstellungen optimieren."
--
-- Befund: am 01.11. 52 Pushes an einen Nutzer (Plus-"Sofort"-Ankündigungen
-- ohne Budget, alle 15 Minuten eine), 0 von 71 Pushes geöffnet.
--
-- 1. Neue Einstellungen (notification_preferences):
--    push_weekly_limit   – Budget für alles außer Wichtigem/Planung (5–40, Standard 10)
--    push_new_followed   – off | weekly | daily | twice_daily
--    push_friends        – off | daily | direct (direkte Anfragen an mich)
--    push_friend_activity – Applaus, Kommentare, "geht auch hin" … als Push
--    push_changes        – Absagen, Verschiebungen, Zeitänderungen
--    push_how_was_it, push_weekly_pick
-- 2. push_candidates():
--    - Neuankündigungen immer gebündelt (kein Plus-Sofort mehr), nur echte
--      Neuheiten (60 Min.–48 Std. alt, keine Dublette, frühestens in 2 Tagen),
--      gefolgte Einträge mit ausgeschalteter Glocke (notify_new_events) zählen nicht
--    - Planung: genau EINE Erinnerung pro Konzert am Konzerttag – für gemerkte,
--      geplante und Abo-Konzerte (Abo mit Wochentags-Variante)
--    - Freunde gesammelt (push_friends = 'daily')
--    - Re-Engagement entfällt (0 % Öffnungen)
-- 3. social_notifications.push_deferred: von notify-social zurückgestellte
--    Freundes-Mitteilungen für die Tages-Sammlung.

alter table public.notification_preferences
  add column if not exists push_weekly_limit smallint not null default 10 check (push_weekly_limit between 3 and 40),
  add column if not exists push_new_followed text not null default 'daily' check (push_new_followed in ('off', 'weekly', 'daily', 'twice_daily')),
  add column if not exists push_friends text not null default 'direct' check (push_friends in ('off', 'daily', 'direct')),
  add column if not exists push_friend_activity boolean not null default false,
  add column if not exists push_changes boolean not null default true,
  add column if not exists push_how_was_it boolean not null default true,
  add column if not exists push_weekly_pick boolean not null default true;

-- Bisherige Schalter übernehmen.
update public.notification_preferences set push_new_followed = 'off' where followed_ensemble_new_event = false;
update public.notification_preferences set push_weekly_pick = false where new_matching_events = false;

alter table public.social_notifications add column if not exists push_deferred boolean not null default false;

-- Erinnerung an Abo-Konzerte serverseitig (statt nur lokal auf einem Gerät).
alter table public.user_concert_subscriptions add column if not exists remind boolean not null default true;

-- Für "schon in einer früheren Sammlung gemeldet": Event-IDs je Sammel-Push.
alter table public.push_log add column if not exists facts_event_ids uuid[] not null default '{}';
create index if not exists push_log_user_kind_idx on public.push_log (user_id, kind, sent_at desc);

create or replace function public.push_candidates()
returns table (user_id uuid, kind text, dedupe_key text, event_id uuid, priority int, transactional boolean, facts jsonb)
language sql stable security definer set search_path = public as $$
  with users as (
    select distinct pt.user_id,
      coalesce(np.push_new_followed, 'daily') as p_followed,
      coalesce(np.almost_sold_out, true) as p_sold,
      coalesce(np.reminder_day_before, true) as p_remind,
      coalesce(np.push_weekly_pick, true) as p_pick,
      coalesce(np.push_how_was_it, true) as p_how,
      coalesce(np.push_friends, 'direct') as p_friends,
      p.display_name, public.is_plus(pt.user_id) as is_plus
    from push_tokens pt
    join profiles p on p.id = pt.user_id
    left join notification_preferences np on np.user_id = pt.user_id
  ),
  ev as (
    select e.id, e.slug, e.title, e.start_datetime, e.remaining_tickets_status, e.doors_info, e.image_urls[1] as image_url,
      v.name as venue_name, v.id as venue_id, e.created_at,
      (select string_agg(coalesce(pe.full_name, en.name), ', ' order by ep.display_order nulls last)
       from event_participants ep left join persons pe on pe.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
       where ep.event_id = e.id) as cast_names,
      (select string_agg(coalesce(c.full_name || ': ', '') || w.title, ' · ' order by ew.position)
       from event_works ew join works w on w.id = ew.work_id left join persons c on c.id = w.composer_id
       where ew.event_id = e.id) as program
    from events e left join venues v on v.id = e.venue_id
    where e.status = 'scheduled' and e.duplicate_of is null and e.start_datetime >= now() - interval '2 days'
  ),
  -- 1. Neu angekündigt von Gefolgten – immer gesammelt.
  --    Zeitraum je Einstellung: täglich, zweimal täglich (nur Plus), wöchentlich (sonntags).
  followed_hits as (
    select u.user_id, u.display_name, u.p_followed, u.is_plus, ev.*,
      coalesce(fp.full_name, fe.name, fv.name) as followed_name
    from users u
    join ev on ev.created_at between now() - interval '48 hours' and now() - interval '60 minutes'
           and ev.start_datetime > now() + interval '2 days'
    left join event_participants ep on ep.event_id = ev.id
    left join persons fp on fp.id = ep.person_id and exists (
      select 1 from user_favorite_persons f where f.user_id = u.user_id and f.person_id = fp.id and f.notify_new_events)
    left join ensembles fe on fe.id = ep.ensemble_id and exists (
      select 1 from user_favorite_ensembles f where f.user_id = u.user_id and f.ensemble_id = fe.id and f.notify_new_events)
    left join venues fv on fv.id = ev.venue_id and exists (
      select 1 from user_favorite_venues f where f.user_id = u.user_id and f.venue_id = fv.id and f.notify_new_events)
    where u.p_followed <> 'off'
      and (u.p_followed <> 'weekly' or extract(isodow from now() at time zone 'Europe/Berlin') = 7)
      and (fp.id is not null or fe.id is not null or fv.id is not null)
      -- Schon in einer früheren Sammlung gemeldet?
      and not exists (select 1 from push_log l where l.user_id = u.user_id and l.kind = 'new_followed' and l.facts_event_ids @> array[ev.id])
  ),
  followed_new as (
    select h.user_id, 'new_followed'::text as kind,
      'new_followed:' || case
        when h.p_followed = 'weekly' then to_char(now() at time zone 'Europe/Berlin', 'IYYY-IW')
        when h.p_followed = 'twice_daily' and h.is_plus then to_char(now() at time zone 'Europe/Berlin', 'YYYY-MM-DD')
          || case when extract(hour from now() at time zone 'Europe/Berlin') < 14 then 'a' else 'b' end
        else to_char(now() at time zone 'Europe/Berlin', 'YYYY-MM-DD') end as dedupe_key,
      (array_agg(h.id order by h.start_datetime))[1] as event_id,
      70 as priority, false as transactional,
      jsonb_build_object('first_name', split_part(coalesce(h.display_name, ''), ' ', 1),
        'count', count(distinct h.id),
        'event_ids', jsonb_agg(distinct h.id),
        'followed', (array_agg(distinct h.followed_name))[1:2],
        'events', (select jsonb_agg(x) from (
          select distinct on (h2.id) jsonb_build_object('title', h2.title, 'start', h2.start_datetime, 'venue', h2.venue_name, 'slug', h2.slug, 'image_url', h2.image_url) x
          from followed_hits h2 where h2.user_id = h.user_id order by h2.id, h2.start_datetime limit 3) s)) as facts
    from followed_hits h
    group by h.user_id, h.display_name, h.p_followed, h.is_plus
  ),
  -- 2. Fast ausverkauft (gemerkt, noch kein "ich gehe hin")
  sold as (
    select u.user_id, 'almost_sold_out', 'almost_sold_out:' || ev.id, ev.id, 80, false,
      jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'cast', ev.cast_names, 'program', ev.program, 'slug', ev.slug, 'image_url', ev.image_url)
    from users u join favorites f on f.user_id = u.user_id and f.status = 'interested'
    join ev on ev.id = f.event_id and ev.remaining_tickets_status = 'few_left' and ev.start_datetime between now() and now() + interval '30 days'
    where u.p_sold
  ),
  -- 3. Planung: genau eine Erinnerung pro Konzert am Konzerttag – gemerkt,
  --    geplant oder im Abo (mit gewählter Wochentags-Variante).
  my_concerts as (
    select f.user_id, f.event_id from favorites f
    union
    select a.user_id, a.event_id from event_attendance a where a.status = 'planned'
    union
    select us.user_id, ecs.event_id
    from user_concert_subscriptions us
    join event_concert_subscriptions ecs on ecs.subscription_id = us.subscription_id
    join events e on e.id = ecs.event_id
    where us.remind and (us.weekday is null or extract(isodow from e.start_datetime at time zone 'Europe/Berlin') = us.weekday)
  ),
  concert_day as (
    select u.user_id, 'concert_day', 'concert:' || ev.id, ev.id, 95, true,
      jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'doors', ev.doors_info, 'cast', ev.cast_names, 'program', ev.program, 'slug', ev.slug, 'image_url', ev.image_url)
    from users u join my_concerts m on m.user_id = u.user_id
    join ev on ev.id = m.event_id
      and (ev.start_datetime at time zone 'Europe/Berlin')::date = (now() at time zone 'Europe/Berlin')::date
      and ev.start_datetime > now() + interval '2 hours'
    where u.p_remind
  ),
  -- 4. "Wie war's?" am Morgen danach
  how_was_it as (
    select u.user_id, 'how_was_it', 'how_was_it:' || e.id, e.id, 60, false,
      jsonb_build_object('title', e.title, 'venue', v.name, 'slug', e.slug, 'image_url', e.image_urls[1])
    from users u join favorites f on f.user_id = u.user_id and f.status = 'attending'
    join events e on e.id = f.event_id
      and (e.start_datetime at time zone 'Europe/Berlin')::date = (now() at time zone 'Europe/Berlin')::date - 1
    left join venues v on v.id = e.venue_id
    where u.p_how and not exists (select 1 from event_ratings r where r.user_id = u.user_id and r.event_id = e.id)
  ),
  -- 5. Wochen-Tipp (donnerstags): das eine beste Konzert
  weekly as (
    select u.user_id, 'weekly_pick', 'weekly_pick:' || to_char(now() at time zone 'Europe/Berlin', 'IYYY-IW'), pick.event_id, 50, false,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1), 'title', pick.title, 'start', pick.start_datetime,
        'venue', pick.venue_name, 'reason', pick.reason_detail, 'slug', pick.slug, 'image_url', pick.image_url,
        'cast', (select cast_names from ev where ev.id = pick.event_id), 'program', (select program from ev where ev.id = pick.event_id))
    from users u
    cross join lateral (select * from newsletter_personal_picks(u.user_id, 10, 1)) pick
    where u.p_pick and extract(isodow from now() at time zone 'Europe/Berlin') = 4
      and not exists (select 1 from favorites f where f.user_id = u.user_id and f.event_id = pick.event_id)
  ),
  -- 6. Freunde, gesammelt (Einstellung "einmal täglich")
  friends as (
    select u.user_id, 'friends_digest', 'friends:' || to_char(now() at time zone 'Europe/Berlin', 'YYYY-MM-DD'), null::uuid, 65, false,
      jsonb_build_object('count', count(*),
        'names', (array_agg(distinct coalesce(p.display_name, 'Jemand')))[1:3],
        'kinds', jsonb_agg(distinct s.kind))
    from users u
    join social_notifications s on s.recipient = u.user_id and s.push_deferred and s.created_at > now() - interval '24 hours'
    left join profiles p on p.id = s.actor
    where u.p_friends = 'daily'
    group by u.user_id
  )
  select c.* from (
    select * from followed_new
    union all select * from sold
    union all select * from concert_day
    union all select * from how_was_it
    union all select * from weekly
    union all select * from friends
  ) c
  where not exists (select 1 from push_log l where l.user_id = c.user_id and l.dedupe_key = c.dedupe_key);
$$;

-- Wöchentliches Budget je Nutzer für den Dispatcher.
create or replace function public.push_user_limits()
returns table (user_id uuid, weekly_limit int)
language sql stable security definer set search_path = public as $$
  select np.user_id, np.push_weekly_limit::int from notification_preferences np where np.push_weekly_limit <> 10
$$;
revoke all on function public.push_user_limits() from public, anon, authenticated;
