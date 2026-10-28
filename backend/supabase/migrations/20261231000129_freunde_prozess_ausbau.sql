-- Erstellt von Claude Code (Freunde-Ausbau, 28.10.2026): zwölf Ideen rund
-- um Freundschaften, Anfragen und gemeinsame Konzerte.
--   1  QR-Code / Code scannen        -> add_friend_by_code meldet invite_accepted
--   2  "Wer war noch da?"            -> concert_companions()
--   3  Einladungslink-Begrüßung      -> accept_friend_invite(), Push invite_accepted
--   4  Push-Aktionen Annehmen/Ablehnen (nur notify-social/App)
--   5  Anfragen mit Kontext          -> friend_requests.source/context_event_id,
--                                       my_friend_requests() mit shared_composers
--   6  Gesendete Anfragen            (nur App, cancel_friend_request existiert)
--   7  Nach dem Annehmen             -> friend_connection()
--   8  Profil: Geschmacks-Match, gemeinsame Geschichte, Bewertungen -> user_profile()
--   9  Freundesliste, enge Freunde   -> close_friends, my_friends() erweitert
--   10 Stummschalten                 -> muted_friends, notify_social() prüft
--   11 "Ticket übrig"                -> ticket_offers + RPCs, Pushes ticket_*
--   12 "Privat hingehen"             -> private_concerts; alle Freunde-RPCs
--                                       blenden diese Konzerte für Freunde aus.
-- Sperren (is_blocked_between) gelten weiterhin überall.

-- ---------------------------------------------------------------------------
-- Tabellen
create table if not exists public.private_concerts (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);
alter table public.private_concerts enable row level security;
create policy "Eigene private Konzerte" on public.private_concerts for select using (user_id = auth.uid());

create table if not exists public.close_friends (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id)
);
alter table public.close_friends enable row level security;
create policy "Eigene enge Freunde" on public.close_friends for select using (user_id = auth.uid());

create table if not exists public.muted_friends (
  user_id uuid not null references auth.users(id) on delete cascade,
  muted_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, muted_id)
);
alter table public.muted_friends enable row level security;
create policy "Eigene Stummschaltungen" on public.muted_friends for select using (user_id = auth.uid());

create table if not exists public.ticket_offers (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  offered_by uuid not null references auth.users(id) on delete cascade,
  note text check (note is null or char_length(note) <= 200),
  status text not null default 'open' check (status in ('open', 'taken', 'withdrawn')),
  taken_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  taken_at timestamptz
);
create unique index if not exists ticket_offers_one_open on public.ticket_offers (event_id, offered_by) where status = 'open';
create index if not exists ticket_offers_open_idx on public.ticket_offers (offered_by) where status = 'open';
alter table public.ticket_offers enable row level security;
-- Zugriff nur über die Funktionen unten.

-- Anfragen: mehr Quellen und optional das Konzert, bei dem man sich traf.
alter table public.friend_requests drop constraint if exists friend_requests_source_check;
alter table public.friend_requests add constraint friend_requests_source_check
  check (source in ('profile', 'contacts', 'suggestion', 'search', 'concert', 'code', 'invite', 'buddy'));
alter table public.friend_requests add column if not exists context_event_id uuid references public.events(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Helfer (nur intern, nicht für Clients freigegeben)
create or replace function public.concert_hidden_from_friends(p_user uuid, p_event uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from private_concerts where user_id = p_user and event_id = p_event);
$$;

-- Geschmacks-Merkmale eines Nutzers: gefolgte Personen/Ensembles,
-- Lieblingsgenres und Komponist:innen besuchter (nicht privater) Konzerte.
create or replace function public.taste_keys(p_user uuid)
returns setof text language sql stable security definer set search_path = public as $$
  select 'p:' || person_id from user_favorite_persons where user_id = p_user
  union
  select 'e:' || ensemble_id from user_favorite_ensembles where user_id = p_user
  union
  select 'g:' || genre_id from profile_interest_genres where user_id = p_user
  union
  select 'c:' || w.composer_id from event_attendance a
    join event_works ew on ew.event_id = a.event_id join works w on w.id = ew.work_id
    where a.user_id = p_user and w.composer_id is not null and not concert_hidden_from_friends(p_user, a.event_id);
$$;

-- Übereinstimmung 0–100 (Kosinus über die Merkmalsmengen), null bei zu
-- wenig Daten auf einer Seite.
create or replace function public.taste_match(a uuid, b uuid)
returns int language sql stable security definer set search_path = public as $$
  with x as (select k from taste_keys(a) k), y as (select k from taste_keys(b) k),
  n as (select (select count(*) from x) as nx, (select count(*) from y) as ny,
               (select count(*) from x join y using (k)) as nxy)
  select case when nx < 3 or ny < 3 then null
              else least(100, round(100.0 * nxy / sqrt(nx::numeric * ny))::int) end
  from n;
$$;

-- Komponist:innen, die beide gern hören (besucht oder gefolgt), höchstens drei.
create or replace function public.shared_composer_names(a uuid, b uuid, p_limit int default 3)
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(name order by name), '{}') from (
    select p.full_name as name from persons p
    where p.id in (
      select substr(k, 3)::uuid from taste_keys(a) k where k like 'c:%' or k like 'p:%'
      intersect
      select substr(k, 3)::uuid from taste_keys(b) k where k like 'c:%' or k like 'p:%')
    order by p.full_name
    limit p_limit
  ) t;
$$;

revoke all on function public.concert_hidden_from_friends(uuid, uuid), public.taste_keys(uuid),
  public.taste_match(uuid, uuid), public.shared_composer_names(uuid, uuid, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 10: Stummschalten. notify_social prüft zusätzlich muted_friends
-- (Schlüssel und URL unverändert aus 000096).
create or replace function public.notify_social(p_kind text, p_recipient uuid, p_actor uuid, p_event_id uuid, p_ref uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if p_recipient is null or p_recipient = p_actor or is_blocked_between(p_recipient, p_actor) then return; end if;
  if p_actor is not null and exists (select 1 from muted_friends where user_id = p_recipient and muted_id = p_actor) then return; end if;
  -- Dieselbe Nachricht höchstens einmal pro Tag.
  if exists (select 1 from social_notifications where kind = p_kind and recipient = p_recipient and actor is not distinct from p_actor
             and event_id is not distinct from p_event_id and created_at > now() - interval '1 day') then return; end if;
  insert into social_notifications(kind, recipient, actor, event_id, ref_id) values (p_kind, p_recipient, p_actor, p_event_id, p_ref);
  begin
    perform net.http_post(
      url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/notify-social',
      body := '{}'::jsonb,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', internal_function_secret(),
        'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
      timeout_milliseconds := 10000);
  exception when others then
    raise warning 'notify_social: % (%)', sqlerrm, sqlstate;
  end;
end; $$;
revoke all on function public.notify_social(text, uuid, uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.set_friend_muted(p_friend_id uuid, p_muted boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_friend_id = auth.uid() then raise exception 'invalid'; end if;
  if p_muted then
    insert into muted_friends(user_id, muted_id) values (auth.uid(), p_friend_id) on conflict do nothing;
  else
    delete from muted_friends where user_id = auth.uid() and muted_id = p_friend_id;
  end if;
end; $$;

-- 9: Enge Freunde (nur echte Freunde).
create or replace function public.set_close_friend(p_friend_id uuid, p_close boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_close then
    if not are_friends(auth.uid(), p_friend_id) then raise exception 'not friends'; end if;
    insert into close_friends(user_id, friend_id) values (auth.uid(), p_friend_id) on conflict do nothing;
  else
    delete from close_friends where user_id = auth.uid() and friend_id = p_friend_id;
  end if;
end; $$;

-- Beim Beenden der Freundschaft und beim Blockieren Markierungen aufräumen.
create or replace function public.friendship_cleanup()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from close_friends where user_id = old.user_id and friend_id = old.friend_id;
  return old;
end; $$;
drop trigger if exists friendship_cleanup on public.friendships;
create trigger friendship_cleanup after delete on public.friendships
  for each row execute function public.friendship_cleanup();

-- ---------------------------------------------------------------------------
-- 12: Privat hingehen
create or replace function public.set_concert_private(p_event_id uuid, p_private boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_private then
    insert into private_concerts(user_id, event_id) values (auth.uid(), p_event_id) on conflict do nothing;
  else
    delete from private_concerts where user_id = auth.uid() and event_id = p_event_id;
  end if;
end; $$;

-- "Ich gehe hin" informiert Freunde nicht, wenn das Konzert privat ist.
create or replace function public.favorites_attending_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_friend uuid;
begin
  if new.status = 'attending' and (tg_op = 'INSERT' or old.status is distinct from 'attending')
     and not concert_hidden_from_friends(new.user_id, new.event_id) then
    for v_friend in
      select f.friend_id from friendships f
      join favorites fav on fav.user_id = f.friend_id and fav.event_id = new.event_id and fav.status = 'attending'
      where f.user_id = new.user_id and not concert_hidden_from_friends(f.friend_id, new.event_id)
    loop
      perform notify_social('friend_also_attending', v_friend, new.user_id, new.event_id, null);
    end loop;
  end if;
  return new;
end; $$;

-- 9: Freundesliste mit engen Freunden, nächstem Konzert und letzter Aktivität.
drop function if exists public.my_friends();
create function public.my_friends()
returns table (friend_id uuid, display_name text, avatar_url text, upcoming_count bigint,
               is_close boolean, is_muted boolean, next_concert timestamptz, last_active timestamptz)
language sql stable security definer set search_path = public as $$
  select f.friend_id, p.display_name, p.avatar_url,
    (select count(*) from favorites fav join events e on e.id = fav.event_id
      where fav.user_id = f.friend_id and fav.status = 'attending' and e.start_datetime >= now()
        and not concert_hidden_from_friends(f.friend_id, e.id)),
    exists (select 1 from close_friends c where c.user_id = auth.uid() and c.friend_id = f.friend_id),
    exists (select 1 from muted_friends m where m.user_id = auth.uid() and m.muted_id = f.friend_id),
    (select min(e.start_datetime) from favorites fav join events e on e.id = fav.event_id
      where fav.user_id = f.friend_id and fav.status = 'attending' and e.start_datetime >= now()
        and not concert_hidden_from_friends(f.friend_id, e.id)),
    case when coalesce(p.share_activity, true) then greatest(
      (select max(fav.created_at) from favorites fav where fav.user_id = f.friend_id and fav.status = 'attending'
        and not concert_hidden_from_friends(f.friend_id, fav.event_id)),
      (select max(coalesce(a.attended_at, a.created_at)) from event_attendance a where a.user_id = f.friend_id
        and not concert_hidden_from_friends(f.friend_id, a.event_id)),
      (select max(r.updated_at) from event_ratings r where r.user_id = f.friend_id
        and not concert_hidden_from_friends(f.friend_id, r.event_id))) end
  from friendships f
  left join profiles p on p.id = f.friend_id
  where f.user_id = auth.uid() and not is_blocked_between(auth.uid(), f.friend_id)
  order by 5 desc, p.display_name nulls last;
$$;

create or replace function public.friends_upcoming_events(p_limit int default 30)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, friend_names text[])
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name,
    array_agg(coalesce(p.display_name, 'Freund:in') order by p.display_name)
  from friendships f
  join favorites fav on fav.user_id = f.friend_id and fav.status = 'attending'
  join events e on e.id = fav.event_id and e.start_datetime >= now() and e.status <> 'draft'
  left join venues v on v.id = e.venue_id
  left join profiles p on p.id = f.friend_id
  where f.user_id = auth.uid() and not concert_hidden_from_friends(f.friend_id, e.id)
  group by e.id, e.slug, e.title, e.start_datetime, v.name
  order by e.start_datetime
  limit least(greatest(p_limit, 1), 100);
$$;

create or replace function public.friends_attending(p_event_id uuid)
returns table (friend_id uuid, display_name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select f.friend_id, p.display_name, p.avatar_url
  from friendships f
  join favorites fav on fav.user_id = f.friend_id and fav.event_id = p_event_id and fav.status = 'attending'
  left join profiles p on p.id = f.friend_id
  where f.user_id = auth.uid() and not concert_hidden_from_friends(f.friend_id, p_event_id);
$$;

create or replace function public.friend_activity(p_limit int default 40)
returns table (kind text, user_id uuid, display_name text, avatar_url text, event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text, stars smallint, comment text, happened_at timestamptz)
language sql stable security definer set search_path = public as $$
  with friends as (
    select f.friend_id as id from friendships f join profiles p on p.id = f.friend_id
    where f.user_id = auth.uid() and p.share_activity
  ), items as (
    select 'attending'::text as kind, fav.user_id, fav.event_id, null::smallint as stars, null::text as comment, fav.created_at as happened_at
      from favorites fav where fav.status = 'attending' and fav.user_id in (select id from friends) and fav.created_at > now() - interval '30 days'
    union all
    select 'attended', a.user_id, a.event_id, null, null, coalesce(a.attended_at, a.created_at)
      from event_attendance a where a.user_id in (select id from friends) and coalesce(a.attended_at, a.created_at) > now() - interval '30 days'
        and not exists (select 1 from event_ratings r where r.user_id = a.user_id and r.event_id = a.event_id)
    union all
    select 'rated', r.user_id, r.event_id, r.stars, r.comment, r.updated_at
      from event_ratings r where r.user_id in (select id from friends) and r.updated_at > now() - interval '30 days'
  )
  select i.kind, i.user_id, coalesce(p.display_name, 'Freund:in'), p.avatar_url, e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1], i.stars, i.comment, i.happened_at
  from items i join events e on e.id = i.event_id left join venues v on v.id = e.venue_id left join profiles p on p.id = i.user_id
  where not concert_hidden_from_friends(i.user_id, i.event_id)
  order by i.happened_at desc
  limit least(greatest(p_limit, 1), 100);
$$;

create or replace function public.friends_popular_events(p_limit int default 14)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text, friend_count bigint, friend_names text[])
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1], count(distinct fav.user_id),
    (array_agg(distinct coalesce(p.display_name, 'Freund:in')))[1:3]
  from friendships f
  join profiles fp on fp.id = f.friend_id and fp.share_activity
  join favorites fav on fav.user_id = f.friend_id
  join events e on e.id = fav.event_id and e.start_datetime >= now() and e.status = 'scheduled'
  left join venues v on v.id = e.venue_id
  left join profiles p on p.id = fav.user_id
  where f.user_id = auth.uid() and not concert_hidden_from_friends(fav.user_id, fav.event_id)
  group by e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1]
  having count(distinct fav.user_id) >= 2
  order by count(distinct fav.user_id) desc, e.start_datetime
  limit least(greatest(p_limit, 1), 30);
$$;

create or replace function public.friend_match_events(p_friend_id uuid, p_limit int default 12)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text, reason text)
language sql stable security definer set search_path = public as $$
  with both_follow_persons as (
    select x.person_id from user_favorite_persons x join user_favorite_persons y on y.person_id = x.person_id
    where x.user_id = auth.uid() and y.user_id = p_friend_id
  ), both_follow_ensembles as (
    select x.ensemble_id from user_favorite_ensembles x join user_favorite_ensembles y on y.ensemble_id = x.ensemble_id
    where x.user_id = auth.uid() and y.user_id = p_friend_id
  ), both_genres as (
    select x.genre_id from profile_interest_genres x join profile_interest_genres y on y.genre_id = x.genre_id
    where x.user_id = auth.uid() and y.user_id = p_friend_id
  ), scored as (
    select e.id,
      3 * (select count(*) from event_participants ep where ep.event_id = e.id and (ep.person_id in (select person_id from both_follow_persons) or ep.ensemble_id in (select ensemble_id from both_follow_ensembles)))
      + (select count(*) from event_genres eg where eg.event_id = e.id and eg.genre_id in (select genre_id from both_genres))
      + 2 * (select count(*) from favorites f where f.event_id = e.id and f.user_id in (auth.uid(), p_friend_id)
               and not concert_hidden_from_friends(f.user_id, e.id)) as score
    from events e
    where e.start_datetime >= now() and e.start_datetime < now() + interval '90 days' and e.status = 'scheduled'
  )
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    case when exists (select 1 from event_participants ep where ep.event_id = e.id and (ep.person_id in (select person_id from both_follow_persons) or ep.ensemble_id in (select ensemble_id from both_follow_ensembles)))
           then 'Ihr folgt beide jemandem aus der Besetzung'
         when exists (select 1 from favorites f where f.event_id = e.id and f.user_id = p_friend_id and not concert_hidden_from_friends(p_friend_id, e.id))
           then 'Schon auf der Merkliste deines Freundes'
         else 'Passt zu euren Lieblingsgenres' end
  from scored s join events e on e.id = s.id left join venues v on v.id = e.venue_id
  where s.score > 0 and are_friends(auth.uid(), p_friend_id)
  order by s.score desc, e.start_datetime
  limit least(greatest(p_limit, 1), 30);
$$;

create or replace function public.shared_concerts_with(p_friend_id uuid, p_year int)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text)
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name
  from event_attendance a
  join event_attendance b on b.event_id = a.event_id and b.user_id = p_friend_id
  join events e on e.id = a.event_id
  left join venues v on v.id = e.venue_id
  where a.user_id = auth.uid() and are_friends(auth.uid(), p_friend_id)
    and not concert_hidden_from_friends(p_friend_id, e.id)
    and extract(year from e.start_datetime at time zone 'Europe/Berlin') = p_year
  order by e.start_datetime;
$$;

create or replace function public.event_ratings_summary(p_event_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'mine', (select jsonb_build_object('stars', stars, 'comment', comment) from event_ratings where user_id = auth.uid() and event_id = p_event_id),
    'friends', coalesce((select jsonb_agg(jsonb_build_object('user_id', r.user_id, 'display_name', coalesce(p.display_name, 'Freund:in'), 'avatar_url', p.avatar_url, 'stars', r.stars, 'comment', r.comment) order by r.updated_at desc)
      from event_ratings r left join profiles p on p.id = r.user_id
      where r.event_id = p_event_id and are_friends(auth.uid(), r.user_id) and not concert_hidden_from_friends(r.user_id, p_event_id)), '[]'::jsonb)
  );
$$;

create or replace function public.friend_echoes(p_limit int default 20)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(t) order by t.updated_at desc), '[]'::jsonb) from (
    select r.user_id, coalesce(p.display_name, 'Freund:in') as display_name, p.avatar_url,
      e.id as event_id, e.slug, e.title, e.start_datetime, v.name as venue_name, e.image_urls[1] as image_url,
      r.stars, r.comment, r.updated_at, r.user_id = auth.uid() as mine,
      (select count(*) from rating_reactions x where x.rating_user = r.user_id and x.event_id = r.event_id and x.kind = 'applause') as applause,
      exists (select 1 from rating_reactions x where x.rating_user = r.user_id and x.event_id = r.event_id and x.kind = 'applause' and x.user_id = auth.uid()) as applauded,
      coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'user_id', x.user_id, 'display_name', coalesce(cp.display_name, 'Freund:in'),
                  'avatar_url', cp.avatar_url, 'body', x.body, 'created_at', x.created_at, 'mine', x.user_id = auth.uid()) order by x.created_at)
                from rating_reactions x left join profiles cp on cp.id = x.user_id
                where x.rating_user = r.user_id and x.event_id = r.event_id and x.kind = 'comment'
                  and not is_blocked_between(auth.uid(), x.user_id)), '[]'::jsonb) as comments
    from event_ratings r
    join profiles p on p.id = r.user_id
    join events e on e.id = r.event_id
    left join venues v on v.id = e.venue_id
    where r.updated_at > now() - interval '60 days'
      and (r.user_id = auth.uid() or (r.user_id in (select friend_id from friendships where user_id = auth.uid()) and p.share_activity
                                      and not concert_hidden_from_friends(r.user_id, r.event_id)))
      and not is_blocked_between(auth.uid(), r.user_id)
    order by r.updated_at desc
    limit least(greatest(p_limit, 1), 50)
  ) t;
$$;

create or replace function public.concert_buddy_suggestions(p_limit int default 8)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text,
               friend_id uuid, display_name text, avatar_url text, reason text, score int)
language sql stable security definer set search_path = public as $$
  with mine as (
    select f.event_id from favorites f
    join events e on e.id = f.event_id and e.start_datetime > now() and e.status in ('scheduled', 'sold_out')
    where f.user_id = auth.uid()
  ),
  friends as (
    select fr.friend_id as id from friendships fr join profiles p on p.id = fr.friend_id
    where fr.user_id = auth.uid() and p.share_activity and not is_blocked_between(auth.uid(), fr.friend_id)
  ),
  candidates as (
    -- hat dasselbe Konzert gemerkt (und nicht privat gestellt)
    select m.event_id, fr.id as friend_id, 'Hat es sich auch gemerkt' as reason, 3 as score
    from mine m join favorites ff on ff.event_id = m.event_id join friends fr on fr.id = ff.user_id
    where not concert_hidden_from_friends(fr.id, m.event_id)
    union all
    -- folgt jemandem, der dort spielt
    select m.event_id, fr.id, 'Folgt ' || coalesce(pe.full_name, en.name), 2
    from mine m
    join event_participants ep on ep.event_id = m.event_id
    left join persons pe on pe.id = ep.person_id
    left join ensembles en on en.id = ep.ensemble_id
    join friends fr on exists (select 1 from user_favorite_persons x where x.user_id = fr.id and x.person_id = ep.person_id)
                    or exists (select 1 from user_favorite_ensembles x where x.user_id = fr.id and x.ensemble_id = ep.ensemble_id)
    union all
    -- hört den Komponisten gern (war schon in Konzerten mit seinen Werken)
    select m.event_id, fr.id, 'Hört gern ' || c.full_name, 1
    from mine m
    join event_works ew on ew.event_id = m.event_id
    join works w on w.id = ew.work_id
    join persons c on c.id = w.composer_id
    join friends fr on exists (
      select 1 from event_attendance a join event_works ew2 on ew2.event_id = a.event_id join works w2 on w2.id = ew2.work_id
      where a.user_id = fr.id and w2.composer_id = c.id and not concert_hidden_from_friends(fr.id, a.event_id))
  ),
  best as (
    select distinct on (c.event_id, c.friend_id) c.event_id, c.friend_id, c.reason, c.score
    from candidates c
    where not exists (
      select 1 from concert_plans pl
      join concert_plan_members a on a.plan_id = pl.id and a.user_id = auth.uid()
      join concert_plan_members b on b.plan_id = pl.id and b.user_id = c.friend_id
      where pl.event_id = c.event_id)
    order by c.event_id, c.friend_id, c.score desc
  )
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    b.friend_id, coalesce(p.display_name, 'Freund:in'), p.avatar_url, b.reason, b.score
  from best b
  join events e on e.id = b.event_id
  left join venues v on v.id = e.venue_id
  join profiles p on p.id = b.friend_id
  order by b.score desc, e.start_datetime
  limit least(greatest(p_limit, 1), 30);
$$;

create or replace function public.shared_year_with(p_friend_id uuid, p_year int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not are_friends(auth.uid(), p_friend_id) or is_blocked_between(auth.uid(), p_friend_id) then return null; end if;
  return (
    with together as (
      select e.id, e.title, e.start_datetime, e.venue_id
      from event_attendance a
      join event_attendance b on b.event_id = a.event_id and b.user_id = p_friend_id
      join events e on e.id = a.event_id
      where a.user_id = auth.uid() and extract(year from e.start_datetime at time zone 'Europe/Berlin') = p_year
        and e.start_datetime <= now() and not concert_hidden_from_friends(p_friend_id, e.id)
    )
    select jsonb_build_object(
      'year', p_year,
      'concerts', (select count(*) from together),
      'first', (select jsonb_build_object('title', title, 'start', start_datetime) from together order by start_datetime limit 1),
      'top_venue', (select v.name from together t join venues v on v.id = t.venue_id group by v.name order by count(*) desc, v.name limit 1),
      'top_composer', (select c.full_name from together t join event_works ew on ew.event_id = t.id join works w on w.id = ew.work_id
                       join persons c on c.id = w.composer_id group by c.full_name order by count(distinct t.id) desc, c.full_name limit 1),
      'plans', (select count(distinct pl.id) from concert_plans pl
                join concert_plan_members a on a.plan_id = pl.id and a.user_id = auth.uid() and a.status = 'going'
                join concert_plan_members b on b.plan_id = pl.id and b.user_id = p_friend_id and b.status = 'going'
                join events e on e.id = pl.event_id
                where extract(year from e.start_datetime at time zone 'Europe/Berlin') = p_year),
      'upcoming', (select count(*) from favorites a join favorites b on b.event_id = a.event_id and b.user_id = p_friend_id
                   join events e on e.id = a.event_id and e.start_datetime > now()
                   where a.user_id = auth.uid() and a.status = 'attending' and b.status = 'attending'
                     and not concert_hidden_from_friends(p_friend_id, e.id))
    )
  );
end; $$;

create or replace function public.my_social_groups()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', g.id, 'name', g.name, 'emoji', g.emoji, 'created_by', g.created_by,
      'members', (select coalesce(jsonb_agg(jsonb_build_object('user_id', m.user_id, 'display_name', coalesce(p.display_name, 'Freund:in'),
                    'avatar_url', p.avatar_url, 'is_friend', are_friends(auth.uid(), m.user_id), 'is_me', m.user_id = auth.uid())
                    order by m.user_id = auth.uid() desc, p.display_name), '[]'::jsonb)
                  from social_group_members m left join profiles p on p.id = m.user_id
                  where m.group_id = g.id and not is_blocked_between(auth.uid(), m.user_id)),
      'upcoming', (select count(distinct f.event_id) from social_group_members m
                   join favorites f on f.user_id = m.user_id and f.status = 'attending'
                   join events e on e.id = f.event_id and e.start_datetime > now()
                   join profiles p on p.id = m.user_id and (p.share_activity or m.user_id = auth.uid())
                   where m.group_id = g.id and (m.user_id = auth.uid() or not concert_hidden_from_friends(m.user_id, f.event_id)))
    ) order by g.created_at desc), '[]'::jsonb)
  from social_groups g
  where is_group_member(g.id);
$$;

create or replace function public.social_group_concerts(p_group_id uuid)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, image_url text,
               people jsonb, i_am_going boolean)
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    jsonb_agg(jsonb_build_object('user_id', m.user_id, 'display_name', coalesce(p.display_name, 'Freund:in'), 'avatar_url', p.avatar_url)
              order by p.display_name),
    bool_or(m.user_id = auth.uid())
  from social_group_members m
  join profiles p on p.id = m.user_id and (p.share_activity or m.user_id = auth.uid())
  join favorites f on f.user_id = m.user_id and f.status = 'attending'
  join events e on e.id = f.event_id and e.start_datetime > now() and e.status in ('scheduled', 'sold_out')
  left join venues v on v.id = e.venue_id
  where m.group_id = p_group_id and is_group_member(p_group_id) and not is_blocked_between(auth.uid(), m.user_id)
    and (m.user_id = auth.uid() or not concert_hidden_from_friends(m.user_id, e.id))
  group by e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1]
  order by e.start_datetime
  limit 40;
$$;

-- ---------------------------------------------------------------------------
-- 8: Profil mit Geschmacks-Match, gemeinsamer Konzertgeschichte und
-- Bewertungen (Basis: 000122). Private Konzerte bleiben verborgen.
create or replace function public.user_profile(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_friend boolean := are_friends(auth.uid(), p_user_id);
  v_profile profiles%rowtype;
  v_self boolean := p_user_id = auth.uid();
begin
  select * into v_profile from profiles where id = p_user_id;
  if v_profile.id is null or is_blocked_between(auth.uid(), p_user_id) then return null; end if;
  if not (v_friend or v_profile.is_public or v_self) then
    return jsonb_build_object('user_id', p_user_id, 'display_name', v_profile.display_name, 'avatar_url', v_profile.avatar_url, 'visible', false,
      'status', case when exists (select 1 from friend_requests r where r.from_user = auth.uid() and r.to_user = p_user_id) then 'requested'
                     when exists (select 1 from friend_requests r where r.from_user = p_user_id and r.to_user = auth.uid()) then 'incoming' else 'none' end);
  end if;
  return jsonb_build_object(
    'user_id', p_user_id, 'display_name', v_profile.display_name, 'avatar_url', v_profile.avatar_url, 'bio', v_profile.bio,
    'visible', true, 'is_friend', v_friend,
    'status', case when v_friend then 'friend'
                   when exists (select 1 from friend_requests r where r.from_user = auth.uid() and r.to_user = p_user_id) then 'requested'
                   when exists (select 1 from friend_requests r where r.from_user = p_user_id and r.to_user = auth.uid()) then 'incoming' else 'none' end,
    'concerts', (select count(*) from event_attendance where user_id = p_user_id)
                + (select count(*) from user_concert_entries where user_id = p_user_id and starts_at <= now()),
    'friends', (select count(*) from friendships where user_id = p_user_id),
    'mutual_friends', (select count(*) from friendships a join friendships b on b.friend_id = a.friend_id where a.user_id = auth.uid() and b.user_id = p_user_id),
    'top_composers', coalesce((
      select jsonb_agg(name) from (
        select c.full_name as name from event_attendance a
        join event_works ew on ew.event_id = a.event_id
        join works w on w.id = ew.work_id
        join persons c on c.id = w.composer_id
        where a.user_id = p_user_id and (v_self or not concert_hidden_from_friends(p_user_id, a.event_id))
        group by c.full_name order by count(distinct a.event_id) desc limit 5) t), '[]'::jsonb),
    'upcoming', coalesce((
      select jsonb_agg(jsonb_build_object('event_id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime, 'venue_name', v.name) order by e.start_datetime)
      from favorites f join events e on e.id = f.event_id left join venues v on v.id = e.venue_id
      where f.user_id = p_user_id and f.status = 'attending' and e.start_datetime >= now() and (v_friend or v_self)
        and (v_self or not concert_hidden_from_friends(p_user_id, e.id))), '[]'::jsonb),
    'taste_match', case when v_self then null else taste_match(auth.uid(), p_user_id) end,
    'shared_composers', case when v_self then '[]'::jsonb else to_jsonb(shared_composer_names(auth.uid(), p_user_id, 6)) end,
    'is_close', exists (select 1 from close_friends where user_id = auth.uid() and friend_id = p_user_id),
    'is_muted', exists (select 1 from muted_friends where user_id = auth.uid() and muted_id = p_user_id),
    -- Ihr wart beide dort (alle Jahre, neueste zuerst).
    'shared_history', case when v_friend then coalesce((
      select jsonb_agg(jsonb_build_object('event_id', t.id, 'slug', t.slug, 'title', t.title, 'start_datetime', t.start_datetime,
                       'venue_name', t.venue_name, 'image_url', t.image_url) order by t.start_datetime desc)
      from (select e.id, e.slug, e.title, e.start_datetime, v.name as venue_name, e.image_urls[1] as image_url
            from event_attendance a
            join event_attendance b on b.event_id = a.event_id and b.user_id = p_user_id
            join events e on e.id = a.event_id left join venues v on v.id = e.venue_id
            where a.user_id = auth.uid() and e.start_datetime <= now() and not concert_hidden_from_friends(p_user_id, e.id)
            order by e.start_datetime desc limit 12) t), '[]'::jsonb) else '[]'::jsonb end,
    -- Bewertungen: nur für Freunde und nur bei geteilter Aktivität.
    'ratings', case when v_friend and v_profile.share_activity then coalesce((
      select jsonb_agg(jsonb_build_object('event_id', t.id, 'slug', t.slug, 'title', t.title, 'start_datetime', t.start_datetime,
                       'venue_name', t.venue_name, 'image_url', t.image_url, 'stars', t.stars, 'comment', t.comment) order by t.updated_at desc)
      from (select e.id, e.slug, e.title, e.start_datetime, v.name as venue_name, e.image_urls[1] as image_url, r.stars, r.comment, r.updated_at
            from event_ratings r join events e on e.id = r.event_id left join venues v on v.id = e.venue_id
            where r.user_id = p_user_id and not concert_hidden_from_friends(p_user_id, r.event_id)
            order by r.updated_at desc limit 20) t), '[]'::jsonb) else '[]'::jsonb end
  );
end; $$;

-- ---------------------------------------------------------------------------
-- 5: Anfragen mit Quelle, Konzert und gemeinsamen Komponist:innen.
drop function if exists public.send_friend_request(uuid, text);
create function public.send_friend_request(p_user_id uuid, p_source text default 'profile', p_event_id uuid default null)
returns text language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_user_id = auth.uid() then raise exception 'invalid'; end if;
  if is_blocked_between(auth.uid(), p_user_id) then return 'blocked'; end if;
  if are_friends(auth.uid(), p_user_id) then return 'already_friends'; end if;
  -- Gegenseitige Anfrage = sofort befreundet.
  if exists (select 1 from friend_requests where from_user = p_user_id and to_user = auth.uid()) then
    delete from friend_requests where from_user = p_user_id and to_user = auth.uid();
    insert into friendships(user_id, friend_id) values (auth.uid(), p_user_id), (p_user_id, auth.uid()) on conflict do nothing;
    perform notify_social('friend_accepted', p_user_id, auth.uid(), null, null);
    return 'friends';
  end if;
  insert into friend_requests(from_user, to_user, source, context_event_id)
    values (auth.uid(), p_user_id,
            case when p_source in ('profile', 'contacts', 'suggestion', 'search', 'concert', 'code', 'invite', 'buddy') then p_source else 'profile' end,
            p_event_id)
    on conflict do nothing;
  perform notify_social('friend_request', p_user_id, auth.uid(), null, null);
  return 'requested';
end; $$;

drop function if exists public.my_friend_requests();
create function public.my_friend_requests()
returns table (user_id uuid, display_name text, avatar_url text, incoming boolean, source text, created_at timestamptz, mutual_friends bigint,
               shared_composers text[], context text)
language sql stable security definer set search_path = public as $$
  select o.other, p.display_name, p.avatar_url, r.to_user = auth.uid(), r.source, r.created_at,
    (select count(*) from friendships a join friendships b on b.friend_id = a.friend_id
      where a.user_id = auth.uid() and b.user_id = o.other),
    shared_composer_names(auth.uid(), o.other, 3),
    case when e.id is not null then e.title || ' am ' || to_char(e.start_datetime at time zone 'Europe/Berlin', 'DD.MM.') end
  from friend_requests r
  cross join lateral (select case when r.to_user = auth.uid() then r.from_user else r.to_user end as other) o
  left join profiles p on p.id = o.other
  left join events e on e.id = r.context_event_id
  where (r.to_user = auth.uid() or r.from_user = auth.uid()) and not is_blocked_between(auth.uid(), o.other)
  order by r.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- 7: Nach dem Verbinden: gemeinsame kommende Konzerte und was der Freund vorhat.
create or replace function public.friend_connection(p_friend_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not are_friends(auth.uid(), p_friend_id) or is_blocked_between(auth.uid(), p_friend_id) then return null; end if;
  return jsonb_build_object(
    'user_id', p_friend_id,
    'display_name', (select display_name from profiles where id = p_friend_id),
    'avatar_url', (select avatar_url from profiles where id = p_friend_id),
    'taste_match', taste_match(auth.uid(), p_friend_id),
    'shared', coalesce((
      select jsonb_agg(jsonb_build_object('event_id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime,
                       'venue_name', v.name, 'image_url', e.image_urls[1], 'reason', 'Habt ihr beide gemerkt') order by e.start_datetime)
      from favorites a join favorites b on b.event_id = a.event_id and b.user_id = p_friend_id
      join events e on e.id = a.event_id and e.start_datetime > now() and e.status in ('scheduled', 'sold_out')
      left join venues v on v.id = e.venue_id
      where a.user_id = auth.uid() and not concert_hidden_from_friends(p_friend_id, e.id)), '[]'::jsonb),
    'upcoming', coalesce((
      select jsonb_agg(jsonb_build_object('event_id', t.id, 'slug', t.slug, 'title', t.title, 'start_datetime', t.start_datetime,
                       'venue_name', t.venue_name, 'image_url', t.image_url) order by t.start_datetime)
      from (select e.id, e.slug, e.title, e.start_datetime, v.name as venue_name, e.image_urls[1] as image_url
            from favorites f join events e on e.id = f.event_id and e.start_datetime > now() and e.status in ('scheduled', 'sold_out')
            left join venues v on v.id = e.venue_id
            where f.user_id = p_friend_id and f.status = 'attending' and not concert_hidden_from_friends(p_friend_id, e.id)
            order by e.start_datetime limit 6) t), '[]'::jsonb)
  );
end; $$;

-- ---------------------------------------------------------------------------
-- 1 + 3: Code, QR-Code und Einladungslink verbinden sofort; die einladende
-- Person bekommt Bescheid (invite_accepted).
create or replace function public.add_friend_by_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_friend uuid;
  v_new int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select user_id into v_friend from friend_codes where code = upper(trim(p_code));
  if v_friend is null then return jsonb_build_object('ok', false, 'reason', 'unknown_code'); end if;
  if v_friend = auth.uid() then return jsonb_build_object('ok', false, 'reason', 'own_code'); end if;
  if is_blocked_between(auth.uid(), v_friend) then return jsonb_build_object('ok', false, 'reason', 'unknown_code'); end if;
  insert into friendships(user_id, friend_id) values (auth.uid(), v_friend), (v_friend, auth.uid()) on conflict do nothing;
  get diagnostics v_new = row_count;
  delete from friend_requests where (from_user = auth.uid() and to_user = v_friend) or (from_user = v_friend and to_user = auth.uid());
  if v_new > 0 then perform notify_social('invite_accepted', v_friend, auth.uid(), null, null); end if;
  return jsonb_build_object('ok', true, 'friend_id', v_friend, 'is_new', v_new > 0,
    'display_name', (select display_name from profiles where id = v_friend));
end; $$;

-- Einladungslink nach Anmeldung/Onboarding: verbinden und gleich die
-- Begrüßung (friend_connection) mitliefern.
create or replace function public.accept_friend_invite(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_result jsonb := add_friend_by_code(p_code);
begin
  if not coalesce((v_result->>'ok')::boolean, false) then return v_result; end if;
  return v_result || jsonb_build_object('connection', friend_connection((v_result->>'friend_id')::uuid));
end; $$;

-- ---------------------------------------------------------------------------
-- 2: "Wer war noch da?" – öffentliche Profile, die in den letzten drei Tagen
-- beim selben Konzert waren (zugesagt oder als besucht markiert).
create or replace function public.concert_companions(p_limit int default 12)
returns table (user_id uuid, display_name text, avatar_url text, event_id uuid, slug text, title text,
               start_datetime timestamptz, venue_name text, image_url text, reason text, status text)
language sql stable security definer set search_path = public as $$
  with mine as (
    select e.id from events e
    where e.start_datetime between now() - interval '3 days' and now()
      and (exists (select 1 from favorites f where f.user_id = auth.uid() and f.event_id = e.id and f.status = 'attending')
           or exists (select 1 from event_attendance a where a.user_id = auth.uid() and a.event_id = e.id))
  ),
  others as (
    select f.user_id, f.event_id from favorites f join mine m on m.id = f.event_id where f.status = 'attending'
    union
    select a.user_id, a.event_id from event_attendance a join mine m on m.id = a.event_id
  ),
  picked as (
    select distinct on (o.user_id) o.user_id, o.event_id
    from others o join events e on e.id = o.event_id
    where o.user_id <> auth.uid()
    order by o.user_id, e.start_datetime desc
  )
  select pk.user_id, p.display_name, p.avatar_url, e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    'Wart beide bei „' || e.title || '“ am ' || to_char(e.start_datetime at time zone 'Europe/Berlin', 'DD.MM.'),
    case when exists (select 1 from friend_requests r where r.from_user = pk.user_id and r.to_user = auth.uid()) then 'incoming' else 'none' end
  from picked pk
  join profiles p on p.id = pk.user_id and p.is_public
  join events e on e.id = pk.event_id
  left join venues v on v.id = e.venue_id
  where not are_friends(auth.uid(), pk.user_id)
    and not is_blocked_between(auth.uid(), pk.user_id)
    and not exists (select 1 from friend_requests r where r.from_user = auth.uid() and r.to_user = pk.user_id)
    and not concert_hidden_from_friends(pk.user_id, pk.event_id)
    and not concert_hidden_from_friends(auth.uid(), pk.event_id)
  order by e.start_datetime desc, p.display_name
  limit least(greatest(p_limit, 1), 30);
$$;

-- ---------------------------------------------------------------------------
-- 11: Ticket übrig
create or replace function public.offer_ticket(p_event_id uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_offer uuid;
  v_friend uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from events where id = p_event_id and start_datetime > now()) then raise exception 'event not upcoming'; end if;
  select id into v_offer from ticket_offers where event_id = p_event_id and offered_by = auth.uid() and status = 'open';
  if v_offer is not null then
    update ticket_offers set note = nullif(left(trim(coalesce(p_note, '')), 200), '') where id = v_offer;
    return v_offer;
  end if;
  insert into ticket_offers(event_id, offered_by, note) values (p_event_id, auth.uid(), nullif(left(trim(coalesce(p_note, '')), 200), ''))
    returning id into v_offer;
  for v_friend in select friend_id from friendships where user_id = auth.uid() loop
    perform notify_social('ticket_offered', v_friend, auth.uid(), p_event_id, v_offer);
  end loop;
  return v_offer;
end; $$;

create or replace function public.withdraw_ticket_offer(p_offer_id uuid)
returns void language sql security definer set search_path = public as $$
  update ticket_offers set status = 'withdrawn' where id = p_offer_id and offered_by = auth.uid() and status = 'open';
$$;

-- Wer zuerst zusagt, bekommt das Ticket (atomar über status = 'open').
create or replace function public.claim_ticket_offer(p_offer_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_offer ticket_offers%rowtype;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into v_offer from ticket_offers where id = p_offer_id;
  if v_offer.id is null or v_offer.offered_by = auth.uid()
     or not are_friends(auth.uid(), v_offer.offered_by) or is_blocked_between(auth.uid(), v_offer.offered_by) then
    return 'not_allowed';
  end if;
  update ticket_offers set status = 'taken', taken_by = auth.uid(), taken_at = now()
    where id = p_offer_id and status = 'open'
      and exists (select 1 from events e where e.id = ticket_offers.event_id and e.start_datetime > now());
  if not found then return 'taken'; end if;
  perform mark_attending(auth.uid(), v_offer.event_id);
  perform notify_social('ticket_claimed', v_offer.offered_by, auth.uid(), v_offer.event_id, p_offer_id);
  return 'ok';
end; $$;

-- Offene Angebote von Freunden plus eigene Angebote (kommende Konzerte),
-- optional auf ein Konzert beschränkt.
create or replace function public.ticket_offers_for_me(p_event_id uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'offer_id', o.id, 'event_id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime,
      'venue_name', v.name, 'image_url', e.image_urls[1], 'note', o.note, 'status', o.status, 'created_at', o.created_at,
      'user_id', o.offered_by, 'display_name', coalesce(p.display_name, 'Freund:in'), 'avatar_url', p.avatar_url,
      'mine', o.offered_by = auth.uid(),
      'taken_by_me', o.taken_by = auth.uid(),
      'taken_by_name', case when o.offered_by = auth.uid() then tp.display_name end
    ) order by e.start_datetime, o.created_at), '[]'::jsonb)
  from ticket_offers o
  join events e on e.id = o.event_id and e.start_datetime > now()
  left join venues v on v.id = e.venue_id
  left join profiles p on p.id = o.offered_by
  left join profiles tp on tp.id = o.taken_by
  where (p_event_id is null or o.event_id = p_event_id)
    and (
      (o.offered_by = auth.uid() and o.status in ('open', 'taken'))
      or (o.taken_by = auth.uid())
      or (o.status = 'open' and are_friends(auth.uid(), o.offered_by) and not is_blocked_between(auth.uid(), o.offered_by))
    );
$$;

-- Konzertseite: privat? eigener Merklisten-Status? (für "Privat hingehen"
-- und "Ticket anbieten").
create or replace function public.event_social_state(p_event_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'is_private', concert_hidden_from_friends(auth.uid(), p_event_id),
    'my_status', (select status from favorites where user_id = auth.uid() and event_id = p_event_id),
    'offers', ticket_offers_for_me(p_event_id)
  );
$$;

create or replace function public.my_private_concerts()
returns setof uuid language sql stable security definer set search_path = public as $$
  select event_id from private_concerts where user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Rechte
do $$
declare f text;
begin
  foreach f in array array[
    'set_friend_muted(uuid,boolean)', 'set_close_friend(uuid,boolean)', 'set_concert_private(uuid,boolean)', 'my_friends()',
    'friends_upcoming_events(int)', 'friends_attending(uuid)', 'friend_activity(int)', 'friends_popular_events(int)',
    'friend_match_events(uuid,int)', 'shared_concerts_with(uuid,int)', 'event_ratings_summary(uuid)', 'friend_echoes(int)',
    'concert_buddy_suggestions(int)', 'shared_year_with(uuid,int)', 'my_social_groups()', 'social_group_concerts(uuid)',
    'user_profile(uuid)', 'send_friend_request(uuid,text,uuid)', 'my_friend_requests()', 'friend_connection(uuid)',
    'add_friend_by_code(text)', 'accept_friend_invite(text)', 'concert_companions(int)', 'offer_ticket(uuid,text)',
    'withdraw_ticket_offer(uuid)', 'claim_ticket_offer(uuid)', 'ticket_offers_for_me(uuid)', 'event_social_state(uuid)',
    'my_private_concerts()']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
