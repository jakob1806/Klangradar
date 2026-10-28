-- Erstellt von Claude Code (Nutzerwunsch 27.10.2026): Konzert-Abos ausbauen.
--
-- 1. "Ich habe dieses Abo" schlug fehl: Die App speichert per Upsert
--    (Prefer: resolution=merge-duplicates), das braucht UPDATE – gewährt war
--    nur select/insert/delete.
-- 2. Abo-Katalog für die neue Übersicht "Abos entdecken" (mit nächstem
--    Termin, Anzahl, Bild und eigenem Status), optional nach Stadt.
-- 3. Aufräumen fehlerhaft erkannter Abos (mphil "Abo F, Subscription G4",
--    Musikverein-Zyklen ohne Namen) und Neuabgleich: BRSO jetzt über den
--    Konzertkalender (sync-event-subscriptions), mphil mit mehreren Abos je
--    Termin.

grant update on public.user_concert_subscriptions to authenticated;

delete from public.concert_subscriptions
where (organizer = 'mphil' and (code ~* 'subscription|abonnement' or code like '%,%'))
   or (organizer = 'musikverein' and name !~ '[A-Za-zÄÖÜäöü]{2}')
   or (organizer = 'brso' and url = 'https://www.brso.de/abonnements/' and code !~ '^[A-Z0-9]{1,3}$');

update public.concert_subscriptions set url = 'https://www.brso.de/konzerte-tickets/abonnements/'
where organizer = 'brso' and url = 'https://www.brso.de/abonnements/';

update public.events set subscriptions_synced_at = null
where start_datetime >= now()
  and (website_url ilike any (array['%brso.de/konzerte%', '%mphil.de/%', '%musikverein.at/konzert%'])
       or external_id ilike any (array['%brso.de/konzerte%', '%mphil.de/%', '%musikverein.at/konzert%']));

-- Abo-Katalog: nur Abos mit kommenden Terminen. p_city_id filtert auf Abos,
-- deren Termine (überwiegend) in dieser Stadt liegen.
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
    a.upcoming, a.next_start, a.last_start, a.image_url, a.venue_name,
    exists (select 1 from user_concert_subscriptions m where m.subscription_id = s.id and m.user_id = auth.uid())
  from concert_subscriptions s
  join agg a on a.subscription_id = s.id
  where p_city_id is null or a.city_id = p_city_id or a.city_id is null
  order by s.organizer_name, s.name;
$$;
revoke all on function public.subscriptions_catalog(uuid) from public;
grant execute on function public.subscriptions_catalog(uuid) to anon, authenticated;
