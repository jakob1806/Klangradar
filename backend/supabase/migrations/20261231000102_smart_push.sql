-- Erstellt von Claude Code (Nutzerwunsch 23.10.2026): Push-Mitteilungen
-- weniger linear, abwechslungsreich, persönlich, mit KI-Texten.
--
-- Aufbau:
--   push_candidates()  sammelt pro Nutzer mögliche Mitteilungen mit Fakten
--                      (jsonb) und Priorität.
--   push-dispatcher    (Edge Function, alle 15 Min) wählt pro Nutzer im
--                      Rahmen von Budget, Ruhezeit und Lernrate aus, lässt
--                      die KI aus den Fakten texten und versendet.
--   push_log           Versand- und Öffnungsprotokoll (Lernen, Budget,
--                      Doppelversand-Schutz).
-- Ersetzt notify-reminders-daily, notify-followed-entity-events und
-- notify-reengagement. notify-changes (Absagen/Preise) und notify-social
-- (Freunde, sofort) bleiben.

create table if not exists public.push_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  dedupe_key text not null,
  event_id uuid references public.events(id) on delete set null,
  title text not null,
  body text not null,
  author text not null default 'template', -- 'ai:<provider>' oder 'template'
  priority int not null,
  sent_at timestamptz not null default now(),
  opened_at timestamptz,
  action text,
  unique (user_id, dedupe_key)
);
create index if not exists push_log_user_sent_idx on public.push_log (user_id, sent_at desc);
alter table public.push_log enable row level security;
create policy "Eigene Mitteilungen lesen" on public.push_log for select using (user_id = auth.uid());

-- App meldet Öffnen bzw. Schnellaktion (Lernen, welche Arten ankommen).
create or replace function public.push_opened(p_log_id bigint, p_action text default null)
returns void language sql security definer set search_path = public as $$
  update push_log set opened_at = coalesce(opened_at, now()), action = coalesce(p_action, action)
  where id = p_log_id and user_id = auth.uid();
$$;
revoke all on function public.push_opened(bigint, text) from public, anon;
grant execute on function public.push_opened(bigint, text) to authenticated;

-- Öffnungsrate je Nutzer und Art (letzte 60 Tage).
create or replace function public.push_engagement()
returns table (user_id uuid, kind text, sent bigint, opened bigint)
language sql stable security definer set search_path = public as $$
  select user_id, kind, count(*), count(opened_at)
  from push_log where sent_at > now() - interval '60 days'
  group by user_id, kind;
$$;

-- Bevorzugte Stunde (Europe/Berlin) aus App-Nutzung, sonst 18 Uhr.
create or replace function public.push_preferred_hours()
returns table (user_id uuid, hour int)
language sql stable security definer set search_path = public as $$
  select user_id, mode() within group (order by extract(hour from viewed_at at time zone 'Europe/Berlin')::int)
  from event_views where viewed_at > now() - interval '45 days' and user_id is not null
  group by user_id having count(*) >= 5;
$$;

-- Kandidaten. Fakten sind bewusst vollständig (die KI darf nur diese nutzen).
create or replace function public.push_candidates()
returns table (user_id uuid, kind text, dedupe_key text, event_id uuid, priority int, transactional boolean, facts jsonb)
language sql stable security definer set search_path = public as $$
  with users as (
    select distinct pt.user_id, coalesce(np.followed_ensemble_new_event, true) as p_followed,
      coalesce(np.almost_sold_out, true) as p_sold, coalesce(np.reminder_day_before, true) as p_remind,
      coalesce(np.new_matching_events, true) as p_match,
      p.display_name, p.active_city_id
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
    where e.status = 'scheduled' and e.start_datetime >= now() - interval '2 days'
  ),
  -- 1. Neu angekündigt von Gefolgten (gesammelt: eine Mitteilung pro Nutzer und Tag)
  followed_new as (
    select u.user_id, 'new_followed'::text as kind,
      'new_followed:' || to_char(now() at time zone 'Europe/Berlin', 'YYYY-MM-DD') as dedupe_key,
      (array_agg(ev.id order by ev.start_datetime))[1] as event_id, 70 as priority, false as transactional,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1),
        'count', count(distinct ev.id),
        'followed', (array_agg(distinct coalesce(fp.full_name, fe.name, fv.name)))[1:3],
        'events', (jsonb_agg(distinct jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'slug', ev.slug, 'image_url', ev.image_url)))) as facts
    from users u
    join ev on ev.created_at > now() - interval '24 hours' and ev.start_datetime > now()
    left join event_participants ep on ep.event_id = ev.id
    left join persons fp on fp.id = ep.person_id and exists (select 1 from user_favorite_persons f where f.user_id = u.user_id and f.person_id = fp.id)
    left join ensembles fe on fe.id = ep.ensemble_id and exists (select 1 from user_favorite_ensembles f where f.user_id = u.user_id and f.ensemble_id = fe.id)
    left join venues fv on fv.id = ev.venue_id and exists (select 1 from user_favorite_venues f where f.user_id = u.user_id and f.venue_id = fv.id)
    where u.p_followed and (fp.id is not null or fe.id is not null or fv.id is not null)
    group by u.user_id, u.display_name
  ),
  -- 2. Fast ausverkauft (gemerkt, noch nicht "ich gehe hin")
  sold as (
    select u.user_id, 'almost_sold_out', 'almost_sold_out:' || ev.id, ev.id, 80, false,
      jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'cast', ev.cast_names, 'program', ev.program, 'slug', ev.slug, 'image_url', ev.image_url)
    from users u join favorites f on f.user_id = u.user_id and f.status = 'interested'
    join ev on ev.id = f.event_id and ev.remaining_tickets_status = 'few_left' and ev.start_datetime between now() and now() + interval '30 days'
    where u.p_sold
  ),
  -- 3. Konzerttag (Vormittag): Einlass, Anreise
  concert_day as (
    select u.user_id, 'concert_day', 'concert_day:' || ev.id, ev.id, 95, true,
      jsonb_build_object('title', ev.title, 'start', ev.start_datetime, 'venue', ev.venue_name, 'doors', ev.doors_info, 'cast', ev.cast_names, 'program', ev.program, 'slug', ev.slug, 'image_url', ev.image_url)
    from users u join favorites f on f.user_id = u.user_id
    join ev on ev.id = f.event_id
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
    where not exists (select 1 from event_ratings r where r.user_id = u.user_id and r.event_id = e.id)
  ),
  -- 5. Wochen-Tipp (donnerstags): das eine beste Konzert
  weekly as (
    select u.user_id, 'weekly_pick', 'weekly_pick:' || to_char(now() at time zone 'Europe/Berlin', 'IYYY-IW'), pick.event_id, 50, false,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1), 'title', pick.title, 'start', pick.start_datetime,
        'venue', pick.venue_name, 'reason', pick.reason_detail, 'slug', pick.slug, 'image_url', pick.image_url,
        'cast', (select cast_names from ev where ev.id = pick.event_id), 'program', (select program from ev where ev.id = pick.event_id))
    from users u
    cross join lateral (select * from newsletter_personal_picks(u.user_id, 10, 1)) pick
    where u.p_match and extract(isodow from now() at time zone 'Europe/Berlin') = 4
      and not exists (select 1 from favorites f where f.user_id = u.user_id and f.event_id = pick.event_id)
  ),
  -- 6. Wiederkehr (3 Wochen inaktiv, höchstens monatlich)
  reengage as (
    select u.user_id, 'reengagement', 'reengagement:' || to_char(now(), 'YYYY-MM'), pick.event_id, 30, false,
      jsonb_build_object('first_name', split_part(coalesce(u.display_name, ''), ' ', 1), 'title', pick.title, 'start', pick.start_datetime,
        'venue', pick.venue_name, 'reason', pick.reason_detail, 'slug', pick.slug, 'image_url', pick.image_url)
    from users u
    cross join lateral (select * from newsletter_personal_picks(u.user_id, 14, 1)) pick
    where u.p_match
      and not exists (select 1 from event_views vw where vw.user_id = u.user_id and vw.viewed_at > now() - interval '21 days')
      and exists (select 1 from event_views vw where vw.user_id = u.user_id)
  )
  select c.* from (
    select * from followed_new
    union all select * from sold
    union all select * from concert_day
    union all select * from how_was_it
    union all select * from weekly
    union all select * from reengage
  ) c
  where not exists (select 1 from push_log l where l.user_id = c.user_id and l.dedupe_key = c.dedupe_key);
$$;

revoke all on function public.push_candidates(), public.push_engagement(), public.push_preferred_hours() from public, anon, authenticated;
grant execute on function public.push_candidates(), public.push_engagement(), public.push_preferred_hours() to service_role;

-- Alte Einzel-Jobs ablösen (ihre Edge Functions bleiben für manuelle Läufe).
do $$
declare j text;
begin
  foreach j in array array['notify-reminders-daily', 'notify-followed-entity-events', 'notify-reengagement'] loop
    if exists (select 1 from cron.job where jobname = j) then perform cron.unschedule(j); end if;
  end loop;
end $$;

create or replace function run_push_dispatcher()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/push-dispatcher',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(), 'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 150000);
exception when others then
  raise warning 'run_push_dispatcher: % (%)', sqlerrm, sqlstate;
end; $$;

select cron.schedule('push-dispatcher', '*/15 * * * *', $$ select run_push_dispatcher(); $$);
