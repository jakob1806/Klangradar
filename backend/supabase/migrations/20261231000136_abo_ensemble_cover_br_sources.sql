-- Erstellt von Claude Code (Nutzerwunsch 29.10.2026):
--
-- 1. Abo-Titelbild = Foto des Ensembles, das in den kommenden Terminen des
--    Abos am häufigsten spielt (nicht mehr das Bild einer Veranstaltung).
--    Ein redaktionell gesetztes Titelbild (Admin → Abos) geht weiter vor,
--    das Veranstaltungsbild bleibt letzte Rückfallebene.
-- 2. Abos beim BR deutlicher finden: Münchner Rundfunkorchester und BR-Chor
--    als neue Ingestion-Quellen (gleicher Konzertkalender-Endpunkt wie
--    brso.de, Parser-Typ "brso"). Bisher standen von 59 bzw. 38 kommenden
--    Konzerten nur je 4 in der Datenbank.
-- 3. Abo-Zuordnung täglich statt wöchentlich neu prüfen (Reihen werden auf
--    den Seiten oft erst später eingetragen).

create or replace function public.subscription_ensemble_photo(p_subscription_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select en.photo_url
  from event_concert_subscriptions es
  join events e on e.id = es.event_id
  join event_participants ep on ep.event_id = e.id
  join ensembles en on en.id = ep.ensemble_id
  where es.subscription_id = p_subscription_id
    and en.photo_url is not null
    and not coalesce(en.is_resolution_placeholder, false)
  group by en.id, en.photo_url
  order by count(*) filter (where e.start_datetime >= now()) desc, count(*) desc
  limit 1;
$$;
grant execute on function public.subscription_ensemble_photo(uuid) to anon, authenticated;

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
    a.upcoming, a.next_start, a.last_start,
    coalesce(s.image_url, subscription_ensemble_photo(s.id), a.image_url),
    a.venue_name,
    exists (select 1 from user_concert_subscriptions m where m.subscription_id = s.id and m.user_id = auth.uid())
  from concert_subscriptions s
  join agg a on a.subscription_id = s.id
  where not s.hidden and s.merged_into is null
    and (p_city_id is null or a.city_id = p_city_id or a.city_id is null)
  order by s.organizer_name, s.name;
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
    a.upcoming, a.next_start, a.last_start,
    coalesce(s.image_url, (select en.photo_url from ensembles en where en.id = p_ensemble_id), subscription_ensemble_photo(s.id), a.image_url),
    a.venue_name,
    exists (select 1 from user_concert_subscriptions m where m.subscription_id = s.id and m.user_id = auth.uid())
  from concert_subscriptions s
  join agg a on a.subscription_id = s.id
  where not s.hidden and s.merged_into is null
    and (a.with_ensemble >= 2 or (a.with_ensemble >= 1 and a.with_ensemble * 2 >= a.upcoming))
  order by a.next_start, s.name
  limit 20;
$$;

-- Neue BR-Quellen (Parser "brso", Endpunkt jeweils auf der eigenen Domain).
insert into public.sources (name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config)
select v.name, 'brso', v.url, null, (select id from regions where type = 'city' and slug = 'munich'), 60,
  'robots.txt geprüft (29.10.2026): Konzertkalender nicht disallowed, Opt-out nur für KI-Trainings-Crawler; gleicher Endpunkt wie brso.de.',
  'active',
  '{"autoPublish": true, "writeOffset": 40, "writeBatchSize": 40, "deferImageEnrichment": true}'::jsonb
from (values
  ('Münchner Rundfunkorchester Konzertkalender', 'https://www.rundfunkorchester.de/konzerte-tickets/konzertkalender/?pagination=1&presented_by=&director=all&location=0&abo=0'),
  ('BR-Chor Konzertkalender', 'https://www.br-chor.de/konzerte-tickets/konzertkalender/?pagination=1&presented_by=&director=all&location=0&abo=0')
) as v(name, url)
where not exists (select 1 from public.sources s where s.url = v.url);

-- Abo-Zuordnung täglich neu prüfen (vorher montags).
select cron.unschedule(jobid) from cron.job where jobname = 'subscription-resync';
select cron.schedule('subscription-resync', '50 3 * * *',
  $$ update events set subscriptions_synced_at = null
     where start_datetime >= now() and status in ('scheduled', 'sold_out')
       and (website_url ~* '(mphil|brso|rundfunkorchester|br-chor|m-k-o|gaertnerplatztheater|musikverein|wienersymphoniker)'
            or external_id ~* '(mphil|brso|rundfunkorchester|br-chor|m-k-o|gaertnerplatztheater|musikverein|wienersymphoniker)') $$);

-- Einmalig sofort: BR-Termine neu zuordnen (neue Reihen-Erkennung).
update public.events set subscriptions_synced_at = null
 where start_datetime >= now() and (website_url ~* '(brso|rundfunkorchester|br-chor)' or external_id ~* '(brso|rundfunkorchester|br-chor)');

notify pgrst, 'reload schema';
