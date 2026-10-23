-- Erstellt von Claude Code: Versand für die E-Mail-Einstellungen aus 000093.
-- Bisher gab es nur die Schalter, aber keinen Versand.
--
-- 1. "Deine Konzertwoche" (notification_preferences.email_weekly_digest):
--    persönlich zugeschnittene Wochenmail, nur nach aktivem Einschalten.
-- 2. "Neue Termine von dir Gefolgten" per E-Mail (email_followed_new_event).
-- 3. Vortags-Erinnerung und Absagen/Verschiebungen gemerkter Konzerte
--    (email_reminder_day_before, email_event_changes).
-- Versendet vom Admin-Portal (Vercel-Cron + Resend), daher alles hier nur
-- für die Service-Rolle.

create table if not exists public.email_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  period_key text not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, kind, period_key)
);
alter table public.email_log enable row level security;

-- Empfänger einer Mail-Art mit Adresse, Name, Stadt und Abmelde-Token.
create or replace function public.email_recipients(p_kind text)
returns table (user_id uuid, email text, display_name text, city_id uuid, city_name text, unsubscribe_token uuid)
language sql stable security definer set search_path = public as $$
  select p.id, u.email, p.display_name, p.active_city_id, r.name, np.email_unsubscribe_token
  from notification_preferences np
  join profiles p on p.id = np.user_id
  join auth.users u on u.id = p.id
  left join regions r on r.id = p.active_city_id
  where u.email is not null
    and u.email_confirmed_at is not null
    and case p_kind
          when 'weekly_digest' then np.email_weekly_digest
          when 'followed_new_event' then np.email_followed_new_event
          when 'event_changes' then np.email_event_changes
          when 'reminder_day_before' then np.email_reminder_day_before
          else false end;
$$;

-- Persönliche Auswahl für die Wochenmail. Punkte:
--   gefolgte Person/Ensemble/Ort im Programm +6, gemerkt +5,
--   Freunde gehen hin +3 pro Freund (max. 9), Lieblingsgenre +2 pro Genre,
--   Stadt des Nutzers Pflicht (falls gesetzt).
create or replace function public.newsletter_personal_picks(p_user uuid, p_days int default 10, p_limit int default 8)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text,
               reason text, reason_detail text, score int)
language sql stable security definer set search_path = public as $$
  with me as (select p_user as id, (select active_city_id from profiles where id = p_user) as city),
  window_events as (
    select e.* from events e
    left join venues v on v.id = e.venue_id
    where e.status = 'scheduled'
      and e.start_datetime >= now() and e.start_datetime < now() + make_interval(days => p_days)
      and ((select city from me) is null or v.city_id = (select city from me))
  ),
  followed as (
    select we.id as event_id, min(coalesce(pe.full_name, en.name, v.name)) as name
    from window_events we
    left join event_participants ep on ep.event_id = we.id
    left join persons pe on pe.id = ep.person_id and exists (select 1 from user_favorite_persons f where f.user_id = p_user and f.person_id = pe.id)
    left join ensembles en on en.id = ep.ensemble_id and exists (select 1 from user_favorite_ensembles f where f.user_id = p_user and f.ensemble_id = en.id)
    left join venues v on v.id = we.venue_id and exists (select 1 from user_favorite_venues f where f.user_id = p_user and f.venue_id = v.id)
    where pe.id is not null or en.id is not null or v.id is not null
    group by we.id
  ),
  scored as (
    select we.id,
      case when fo.event_id is not null then 6 else 0 end
      + case when exists (select 1 from favorites f where f.user_id = p_user and f.event_id = we.id) then 5 else 0 end
      + least(9, 3 * (select count(*) from friendships fr join favorites f on f.user_id = fr.friend_id and f.event_id = we.id and f.status = 'attending' where fr.user_id = p_user))
      + 2 * (select count(*) from event_genres eg join profile_interest_genres g on g.genre_id = eg.genre_id and g.user_id = p_user where eg.event_id = we.id)
      as score,
      fo.name as followed_name,
      exists (select 1 from favorites f where f.user_id = p_user and f.event_id = we.id) as saved,
      (select count(*) from friendships fr join favorites f on f.user_id = fr.friend_id and f.event_id = we.id and f.status = 'attending' where fr.user_id = p_user) as friends
    from window_events we left join followed fo on fo.event_id = we.id
  )
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    case when s.saved then 'saved' when s.followed_name is not null then 'followed' when s.friends > 0 then 'friends' else 'taste' end,
    case when s.saved then 'Auf deiner Merkliste'
         when s.followed_name is not null then 'Mit ' || s.followed_name
         when s.friends > 0 then s.friends || case when s.friends = 1 then ' Freund:in geht hin' else ' Freunde gehen hin' end
         else 'Passt zu deinen Lieblingsgenres' end,
    s.score::int
  from scored s join events e on e.id = s.id left join venues v on v.id = e.venue_id
  where s.score > 0
  order by s.score desc, e.start_datetime
  limit least(greatest(p_limit, 1), 20);
$$;

-- Neue Termine (in den letzten p_hours angelegt) von Gefolgten.
create or replace function public.followed_new_events_for(p_user uuid, p_hours int default 24)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text, followed_name text)
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    min(coalesce(pe.full_name, en.name, fv.name))
  from events e
  left join venues v on v.id = e.venue_id
  left join event_participants ep on ep.event_id = e.id
  left join persons pe on pe.id = ep.person_id and exists (select 1 from user_favorite_persons f where f.user_id = p_user and f.person_id = pe.id)
  left join ensembles en on en.id = ep.ensemble_id and exists (select 1 from user_favorite_ensembles f where f.user_id = p_user and f.ensemble_id = en.id)
  left join venues fv on fv.id = e.venue_id and exists (select 1 from user_favorite_venues f where f.user_id = p_user and f.venue_id = fv.id)
  where e.created_at >= now() - make_interval(hours => p_hours)
    and e.start_datetime >= now() and e.status = 'scheduled'
    and (pe.id is not null or en.id is not null or fv.id is not null)
  group by e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1]
  order by e.start_datetime
  limit 12;
$$;

-- Gemerkte Konzerte morgen (Münchner Kalendertag) für die Vortags-Erinnerung.
create or replace function public.saved_events_tomorrow(p_user uuid)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text, detail text)
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    case when f.status = 'attending' then 'Du gehst hin' else 'Auf deiner Merkliste' end
  from favorites f join events e on e.id = f.event_id left join venues v on v.id = e.venue_id
  where f.user_id = p_user and e.status = 'scheduled'
    and (e.start_datetime at time zone 'Europe/Berlin')::date = ((now() at time zone 'Europe/Berlin')::date + 1)
  order by e.start_datetime;
$$;

-- Gemerkte Konzerte, die in den letzten 24 h abgesagt oder verschoben wurden.
create or replace function public.saved_events_changed(p_user uuid)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text, detail text)
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    case e.status when 'cancelled' then 'Abgesagt' when 'postponed' then 'Verschoben' else 'Geändert' end
  from favorites f join events e on e.id = f.event_id left join venues v on v.id = e.venue_id
  where f.user_id = p_user and e.status in ('cancelled', 'postponed')
    and e.updated_at >= now() - interval '24 hours'
    and e.start_datetime >= now() - interval '1 day'
  order by e.start_datetime;
$$;

-- Ein-Klick-Abmeldung per Token (ohne Login).
create or replace function public.email_unsubscribe(p_token uuid, p_kind text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update notification_preferences set
    email_weekly_digest = case when p_kind in ('weekly_digest', 'all') then false else email_weekly_digest end,
    email_followed_new_event = case when p_kind in ('followed_new_event', 'all') then false else email_followed_new_event end,
    email_event_changes = case when p_kind in ('event_changes', 'all') then false else email_event_changes end,
    email_reminder_day_before = case when p_kind in ('reminder_day_before', 'all') then false else email_reminder_day_before end
  where email_unsubscribe_token = p_token;
  return found;
end; $$;

revoke all on function public.email_recipients(text), public.newsletter_personal_picks(uuid,int,int),
  public.followed_new_events_for(uuid,int), public.saved_events_tomorrow(uuid), public.saved_events_changed(uuid), public.email_unsubscribe(uuid,text) from public, anon, authenticated;
grant execute on function public.email_recipients(text), public.newsletter_personal_picks(uuid,int,int),
  public.followed_new_events_for(uuid,int), public.saved_events_tomorrow(uuid), public.saved_events_changed(uuid), public.email_unsubscribe(uuid,text) to service_role;
