-- Erstellt von Claude Code: Social-Ausbau auf Basis von friends (000027).
--
-- 1  Konzertabend planen (concert_plans + Mitglieder, Treffpunkt/Uhrzeit)
-- 2  "Wer kommt mit?" (Plan ohne Treffpunkt; Zusage setzt "Ich gehe hin")
-- 3  Gemeinsame Listen (favorite_list_members)
-- 4  Passende Termine für zwei (friend_match_events)
-- 5  Freunde-Feed (friend_activity, abschaltbar)
-- 6  Kurzbewertung nach dem Konzert (event_ratings)
-- 7  Push "X geht auch hin" (Trigger -> notify-social)
-- 8  Profile: Bio, öffentlich sichtbar, Suche, Freundschaftsanfragen
-- 9  "Beliebt bei Freunden" (friends_popular_events)
-- 10 Gemeinsame Konzerte im Jahr (shared_concerts_with)
-- +  Kontakte finden (gehashte E-Mail/Telefon, nur mit Einwilligung),
--    vorgeschlagene Kontakte, Einladungslink, Blockieren/Melden.
--
-- Datenschutz-Grundsatz: Standard ist "nur Freunde". Öffentliches Profil,
-- Auffindbarkeit über Kontakte und Aktivitäts-Feed sind einzeln steuerbar.

-- ---------------------------------------------------------------------------
-- Profil-Einstellungen
alter table public.profiles
  add column if not exists bio text check (bio is null or char_length(bio) <= 160),
  add column if not exists is_public boolean not null default false,
  add column if not exists share_activity boolean not null default true,
  add column if not exists contact_discoverable boolean not null default false,
  add column if not exists phone_hash text;

-- ---------------------------------------------------------------------------
-- Blockieren (vor allem anderen, alle Funktionen respektieren es)
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
alter table public.user_blocks enable row level security;
create policy "Eigene Blockierungen" on public.user_blocks for select using (blocker_id = auth.uid());

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_blocks where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships where user_id = a and friend_id = b);
$$;

create or replace function public.block_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_user_id = auth.uid() then raise exception 'invalid'; end if;
  insert into user_blocks(blocker_id, blocked_id) values (auth.uid(), p_user_id) on conflict do nothing;
  delete from friendships where (user_id = auth.uid() and friend_id = p_user_id) or (user_id = p_user_id and friend_id = auth.uid());
  delete from friend_requests where (from_user = auth.uid() and to_user = p_user_id) or (from_user = p_user_id and to_user = auth.uid());
end; $$;

create or replace function public.unblock_user(p_user_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from user_blocks where blocker_id = auth.uid() and blocked_id = p_user_id;
$$;

-- Nutzer melden (Redaktion prüft im Supabase-Dashboard).
create table if not exists public.user_reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in ('spam', 'inappropriate', 'impersonation', 'other')),
  message text check (message is null or char_length(message) <= 500),
  created_at timestamptz not null default now()
);
alter table public.user_reports enable row level security;
create policy "Redaktion liest Nutzermeldungen" on public.user_reports for select using (is_admin_or_editor());

create or replace function public.report_user(p_user_id uuid, p_reason text, p_message text default null)
returns void language sql security definer set search_path = public as $$
  insert into user_reports(reporter_id, reported_id, reason, message) values (auth.uid(), p_user_id, p_reason, nullif(trim(p_message), ''));
$$;

-- ---------------------------------------------------------------------------
-- Freundschaftsanfragen (Kontakte, Vorschläge, öffentliche Profile).
-- Der Freundescode/-link (000027) verbindet weiterhin sofort.
create table if not exists public.friend_requests (
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  source text not null default 'profile' check (source in ('profile', 'contacts', 'suggestion', 'search')),
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);
alter table public.friend_requests enable row level security;
create policy "Eigene Anfragen lesen" on public.friend_requests for select using (from_user = auth.uid() or to_user = auth.uid());

create or replace function public.send_friend_request(p_user_id uuid, p_source text default 'profile')
returns text language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_user_id = auth.uid() then raise exception 'invalid'; end if;
  if is_blocked_between(auth.uid(), p_user_id) then return 'blocked'; end if;
  if are_friends(auth.uid(), p_user_id) then return 'already_friends'; end if;
  -- Gegenseitige Anfrage = sofort befreundet.
  if exists (select 1 from friend_requests where from_user = p_user_id and to_user = auth.uid()) then
    delete from friend_requests where from_user = p_user_id and to_user = auth.uid();
    insert into friendships(user_id, friend_id) values (auth.uid(), p_user_id), (p_user_id, auth.uid()) on conflict do nothing;
    return 'friends';
  end if;
  insert into friend_requests(from_user, to_user, source) values (auth.uid(), p_user_id, coalesce(p_source, 'profile')) on conflict do nothing;
  perform notify_social('friend_request', p_user_id, auth.uid(), null, null);
  return 'requested';
end; $$;

create or replace function public.respond_friend_request(p_user_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from friend_requests where from_user = p_user_id and to_user = auth.uid()) then return; end if;
  delete from friend_requests where from_user = p_user_id and to_user = auth.uid();
  if p_accept then
    insert into friendships(user_id, friend_id) values (auth.uid(), p_user_id), (p_user_id, auth.uid()) on conflict do nothing;
    perform notify_social('friend_accepted', p_user_id, auth.uid(), null, null);
  end if;
end; $$;

create or replace function public.cancel_friend_request(p_user_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from friend_requests where from_user = auth.uid() and to_user = p_user_id;
$$;

create or replace function public.my_friend_requests()
returns table (user_id uuid, display_name text, avatar_url text, incoming boolean, source text, created_at timestamptz, mutual_friends bigint)
language sql stable security definer set search_path = public as $$
  select case when r.to_user = auth.uid() then r.from_user else r.to_user end,
    p.display_name, p.avatar_url, r.to_user = auth.uid(), r.source, r.created_at,
    (select count(*) from friendships a join friendships b on b.friend_id = a.friend_id
      where a.user_id = auth.uid() and b.user_id = case when r.to_user = auth.uid() then r.from_user else r.to_user end)
  from friend_requests r
  left join profiles p on p.id = case when r.to_user = auth.uid() then r.from_user else r.to_user end
  where r.to_user = auth.uid() or r.from_user = auth.uid()
  order by r.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- Kontakte finden: Die App schickt nur SHA-256-Hashes normalisierter
-- E-Mail-Adressen/Telefonnummern, nie Klartext. Gefunden wird nur, wer
-- contact_discoverable eingeschaltet hat.
create or replace function public.set_contact_discovery(p_enabled boolean, p_phone_hash text default null)
returns void language sql security definer set search_path = public as $$
  update profiles set contact_discoverable = p_enabled,
    phone_hash = case when p_enabled then coalesce(p_phone_hash, phone_hash) else null end
  where id = auth.uid();
$$;

create or replace function public.match_contacts(p_hashes text[])
returns table (user_id uuid, display_name text, avatar_url text, status text)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, p.display_name, p.avatar_url,
    case when are_friends(auth.uid(), p.id) then 'friend'
         when exists (select 1 from friend_requests r where r.from_user = auth.uid() and r.to_user = p.id) then 'requested'
         when exists (select 1 from friend_requests r where r.from_user = p.id and r.to_user = auth.uid()) then 'incoming'
         else 'none' end
  from profiles p
  join auth.users u on u.id = p.id
  where p.contact_discoverable
    and p.id <> auth.uid()
    and not is_blocked_between(auth.uid(), p.id)
    and (encode(sha256(convert_to(lower(trim(u.email)), 'UTF8')), 'hex') = any(p_hashes[1:2000])
         or (p.phone_hash is not null and p.phone_hash = any(p_hashes[1:2000])));
$$;

-- Vorgeschlagene Kontakte: Freunde von Freunden und Menschen mit ähnlichem
-- Geschmack (gemeinsam gefolgte Künstler:innen), nur öffentliche oder über
-- gemeinsame Freunde verbundene Profile.
create or replace function public.suggested_friends(p_limit int default 20)
returns table (user_id uuid, display_name text, avatar_url text, mutual_friends bigint, shared_follows bigint, reason text)
language sql stable security definer set search_path = public as $$
  with me as (select auth.uid() as id),
  candidates as (
    select b.friend_id as id, count(*) as mutual
    from friendships a join friendships b on b.user_id = a.friend_id
    where a.user_id = (select id from me) and b.friend_id <> (select id from me)
    group by b.friend_id
    union
    select p.id, 0 from profiles p where p.is_public and p.id <> (select id from me)
  ),
  scored as (
    select c.id, max(c.mutual) as mutual,
      (select count(*) from user_favorite_persons x join user_favorite_persons y on y.person_id = x.person_id
        where x.user_id = (select id from me) and y.user_id = c.id)
      + (select count(*) from user_favorite_ensembles x join user_favorite_ensembles y on y.ensemble_id = x.ensemble_id
        where x.user_id = (select id from me) and y.user_id = c.id) as shared
    from candidates c group by c.id
  )
  select s.id, p.display_name, p.avatar_url, s.mutual, s.shared,
    case when s.mutual > 0 then s.mutual || case when s.mutual = 1 then ' gemeinsame:r Freund:in' else ' gemeinsame Freunde' end
         when s.shared > 0 then 'Ähnlicher Musikgeschmack'
         else 'Neu auf Klangradar' end
  from scored s join profiles p on p.id = s.id
  where not are_friends((select id from me), s.id)
    and not is_blocked_between((select id from me), s.id)
    and not exists (select 1 from friend_requests r where r.from_user = (select id from me) and r.to_user = s.id)
    and (s.mutual > 0 or s.shared > 0)
  order by s.mutual desc, s.shared desc
  limit least(greatest(p_limit, 1), 50);
$$;

-- Öffentliche Profile suchen (nur is_public).
create or replace function public.search_profiles(p_query text)
returns table (user_id uuid, display_name text, avatar_url text, bio text, status text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url, p.bio,
    case when are_friends(auth.uid(), p.id) then 'friend'
         when exists (select 1 from friend_requests r where r.from_user = auth.uid() and r.to_user = p.id) then 'requested'
         else 'none' end
  from profiles p
  where (p.is_public or are_friends(auth.uid(), p.id))
    and p.id <> auth.uid()
    and char_length(trim(p_query)) >= 2
    and p.display_name ilike '%' || replace(replace(trim(p_query), '%', ''), '_', '') || '%'
    and not is_blocked_between(auth.uid(), p.id)
  order by are_friends(auth.uid(), p.id) desc, p.display_name
  limit 30;
$$;

-- Profilseite eines anderen Nutzers: für Freunde und bei öffentlichen
-- Profilen. Kennzahlen aus event_attendance, Lieblingskomponist:innen aus
-- besuchten Werken.
create or replace function public.user_profile(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_friend boolean := are_friends(auth.uid(), p_user_id);
  v_profile profiles%rowtype;
begin
  select * into v_profile from profiles where id = p_user_id;
  if v_profile.id is null or is_blocked_between(auth.uid(), p_user_id) then return null; end if;
  if not (v_friend or v_profile.is_public or p_user_id = auth.uid()) then
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
    'concerts', (select count(*) from event_attendance where user_id = p_user_id),
    'friends', (select count(*) from friendships where user_id = p_user_id),
    'mutual_friends', (select count(*) from friendships a join friendships b on b.friend_id = a.friend_id where a.user_id = auth.uid() and b.user_id = p_user_id),
    'top_composers', coalesce((
      select jsonb_agg(name) from (
        select c.full_name as name from event_attendance a
        join event_works ew on ew.event_id = a.event_id
        join works w on w.id = ew.work_id
        join persons c on c.id = w.composer_id
        where a.user_id = p_user_id
        group by c.full_name order by count(distinct a.event_id) desc limit 5) t), '[]'::jsonb),
    'upcoming', coalesce((
      select jsonb_agg(jsonb_build_object('event_id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime, 'venue_name', v.name) order by e.start_datetime)
      from favorites f join events e on e.id = f.event_id left join venues v on v.id = e.venue_id
      where f.user_id = p_user_id and f.status = 'attending' and e.start_datetime >= now() and (v_friend or p_user_id = auth.uid())), '[]'::jsonb)
  );
end; $$;

create or replace function public.update_social_settings(p_bio text, p_is_public boolean, p_share_activity boolean)
returns void language sql security definer set search_path = public as $$
  update profiles set bio = nullif(left(trim(coalesce(p_bio, '')), 160), ''), is_public = p_is_public, share_activity = p_share_activity
  where id = auth.uid();
$$;

create or replace function public.my_social_settings()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('bio', bio, 'is_public', is_public, 'share_activity', share_activity, 'contact_discoverable', contact_discoverable)
  from profiles where id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 1 + 2: Konzertpläne
create table if not exists public.concert_plans (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  meeting_point text check (meeting_point is null or char_length(meeting_point) <= 120),
  meeting_time timestamptz,
  note text check (note is null or char_length(note) <= 280),
  created_at timestamptz not null default now()
);
create table if not exists public.concert_plan_members (
  plan_id uuid not null references public.concert_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'invited' check (status in ('invited', 'going', 'maybe', 'declined')),
  responded_at timestamptz,
  primary key (plan_id, user_id)
);
alter table public.concert_plans enable row level security;
alter table public.concert_plan_members enable row level security;
-- Security-definer-Helfer statt Selbstbezug in der Policy (sonst
-- "infinite recursion detected in policy").
create or replace function public.is_plan_member(p_plan_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from concert_plan_members where plan_id = p_plan_id and user_id = auth.uid());
$$;
create policy "Mitglieder sehen Plan" on public.concert_plans for select using (is_plan_member(id));
create policy "Mitglieder sehen Teilnehmende" on public.concert_plan_members for select using (is_plan_member(plan_id));

create or replace function public.mark_attending(p_user_id uuid, p_event_id uuid)
returns void language sql security definer set search_path = public as $$
  insert into favorites(user_id, event_id, status) values (p_user_id, p_event_id, 'attending')
  on conflict (user_id, event_id) do update set status = 'attending';
$$;
revoke all on function public.mark_attending(uuid, uuid) from public, anon, authenticated;

create or replace function public.create_concert_plan(p_event_id uuid, p_friend_ids uuid[], p_meeting_point text default null, p_meeting_time timestamptz default null, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_plan uuid;
  v_friend uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into concert_plans(event_id, created_by, meeting_point, meeting_time, note)
    values (p_event_id, auth.uid(), nullif(trim(p_meeting_point), ''), p_meeting_time, nullif(trim(p_note), ''))
    returning id into v_plan;
  insert into concert_plan_members(plan_id, user_id, status, responded_at) values (v_plan, auth.uid(), 'going', now());
  perform mark_attending(auth.uid(), p_event_id);
  foreach v_friend in array coalesce(p_friend_ids, '{}') loop
    -- Nur echte Freunde einladen.
    if are_friends(auth.uid(), v_friend) and not is_blocked_between(auth.uid(), v_friend) then
      insert into concert_plan_members(plan_id, user_id) values (v_plan, v_friend) on conflict do nothing;
      perform notify_social('plan_invite', v_friend, auth.uid(), p_event_id, v_plan);
    end if;
  end loop;
  return v_plan;
end; $$;

create or replace function public.respond_concert_plan(p_plan_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid;
  v_creator uuid;
begin
  if p_status not in ('going', 'maybe', 'declined') then raise exception 'invalid status'; end if;
  update concert_plan_members set status = p_status, responded_at = now()
    where plan_id = p_plan_id and user_id = auth.uid();
  if not found then return; end if;
  select event_id, created_by into v_event, v_creator from concert_plans where id = p_plan_id;
  if p_status = 'going' then perform mark_attending(auth.uid(), v_event); end if;
  if v_creator <> auth.uid() then perform notify_social('plan_' || p_status, v_creator, auth.uid(), v_event, p_plan_id); end if;
end; $$;

create or replace function public.update_concert_plan(p_plan_id uuid, p_meeting_point text, p_meeting_time timestamptz, p_note text)
returns void language sql security definer set search_path = public as $$
  update concert_plans set meeting_point = nullif(trim(p_meeting_point), ''), meeting_time = p_meeting_time, note = nullif(trim(p_note), '')
  where id = p_plan_id and created_by = auth.uid();
$$;

create or replace function public.leave_concert_plan(p_plan_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from concert_plans where id = p_plan_id and created_by = auth.uid()) then
    delete from concert_plans where id = p_plan_id;
  else
    delete from concert_plan_members where plan_id = p_plan_id and user_id = auth.uid();
  end if;
end; $$;

create or replace function public.invite_to_plan(p_plan_id uuid, p_friend_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_friend uuid; v_event uuid;
begin
  select event_id into v_event from concert_plans p where p.id = p_plan_id
    and exists (select 1 from concert_plan_members m where m.plan_id = p.id and m.user_id = auth.uid());
  if v_event is null then return; end if;
  foreach v_friend in array coalesce(p_friend_ids, '{}') loop
    if are_friends(auth.uid(), v_friend) then
      insert into concert_plan_members(plan_id, user_id) values (p_plan_id, v_friend) on conflict do nothing;
      if found then perform notify_social('plan_invite', v_friend, auth.uid(), v_event, p_plan_id); end if;
    end if;
  end loop;
end; $$;

create or replace function public.my_concert_plans()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(plan order by (plan->>'start_datetime')), '[]'::jsonb) from (
    select jsonb_build_object(
      'plan_id', p.id, 'event_id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime,
      'venue_name', v.name, 'image_url', e.image_urls[1],
      'meeting_point', p.meeting_point, 'meeting_time', p.meeting_time, 'note', p.note,
      'created_by', p.created_by, 'is_owner', p.created_by = auth.uid(),
      'my_status', me.status,
      'members', (select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'display_name', coalesce(pr.display_name, 'Freund:in'),
                    'avatar_url', pr.avatar_url, 'status', m.status) order by m.status = 'going' desc, pr.display_name)
                  from concert_plan_members m left join profiles pr on pr.id = m.user_id where m.plan_id = p.id)
    ) as plan
    from concert_plans p
    join concert_plan_members me on me.plan_id = p.id and me.user_id = auth.uid()
    join events e on e.id = p.event_id
    left join venues v on v.id = e.venue_id
    where e.start_datetime >= now() - interval '6 hours'
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- 3: Gemeinsame Listen
create table if not exists public.favorite_list_members (
  list_id uuid not null references public.favorite_lists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (list_id, user_id)
);
alter table public.favorite_list_members enable row level security;

create or replace function public.is_list_member(p_list_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from favorite_lists where id = p_list_id and user_id = auth.uid())
      or exists (select 1 from favorite_list_members where list_id = p_list_id and user_id = auth.uid());
$$;

create policy "Mitglieder sehen Listenmitglieder" on public.favorite_list_members for select using (is_list_member(list_id));
create policy "Mitglieder lesen geteilte Listen" on public.favorite_lists for select using (is_list_member(id));
create policy "Mitglieder bearbeiten Einträge geteilter Listen" on public.favorite_list_items for all
  using (is_list_member(list_id)) with check (is_list_member(list_id));

create or replace function public.share_list_with_friends(p_list_id uuid, p_friend_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_friend uuid;
begin
  if not exists (select 1 from favorite_lists where id = p_list_id and user_id = auth.uid()) then raise exception 'not owner'; end if;
  foreach v_friend in array coalesce(p_friend_ids, '{}') loop
    if are_friends(auth.uid(), v_friend) then
      insert into favorite_list_members(list_id, user_id) values (p_list_id, v_friend) on conflict do nothing;
      if found then perform notify_social('list_shared', v_friend, auth.uid(), null, p_list_id); end if;
    end if;
  end loop;
end; $$;

create or replace function public.remove_list_member(p_list_id uuid, p_user_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from favorite_list_members where list_id = p_list_id and user_id = p_user_id
    and (p_user_id = auth.uid() or exists (select 1 from favorite_lists where id = p_list_id and user_id = auth.uid()));
$$;

create or replace function public.list_members(p_list_id uuid)
returns table (user_id uuid, display_name text, avatar_url text, is_owner boolean)
language sql stable security definer set search_path = public as $$
  select l.user_id, p.display_name, p.avatar_url, true from favorite_lists l left join profiles p on p.id = l.user_id
    where l.id = p_list_id and is_list_member(p_list_id)
  union all
  select m.user_id, p.display_name, p.avatar_url, false from favorite_list_members m left join profiles p on p.id = m.user_id
    where m.list_id = p_list_id and is_list_member(p_list_id);
$$;

-- Mit mir geteilte Listen (für die Listenübersicht).
create or replace function public.lists_shared_with_me()
returns table (list_id uuid, name text, owner_name text, cover_image_url text, item_count bigint)
language sql stable security definer set search_path = public as $$
  select l.id, l.name, coalesce(p.display_name, 'Freund:in'), l.cover_image_url,
    (select count(*) from favorite_list_items i where i.list_id = l.id)
  from favorite_list_members m join favorite_lists l on l.id = m.list_id left join profiles p on p.id = l.user_id
  where m.user_id = auth.uid()
  order by m.added_at desc;
$$;

-- ---------------------------------------------------------------------------
-- 4: Passende Termine für zwei
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
      + 2 * (select count(*) from favorites f where f.event_id = e.id and f.user_id in (auth.uid(), p_friend_id)) as score
    from events e
    where e.start_datetime >= now() and e.start_datetime < now() + interval '90 days' and e.status = 'scheduled'
  )
  select e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1],
    case when exists (select 1 from event_participants ep where ep.event_id = e.id and (ep.person_id in (select person_id from both_follow_persons) or ep.ensemble_id in (select ensemble_id from both_follow_ensembles)))
           then 'Ihr folgt beide jemandem aus der Besetzung'
         when exists (select 1 from favorites f where f.event_id = e.id and f.user_id = p_friend_id) then 'Schon auf der Merkliste deines Freundes'
         else 'Passt zu euren Lieblingsgenres' end
  from scored s join events e on e.id = s.id left join venues v on v.id = e.venue_id
  where s.score > 0 and are_friends(auth.uid(), p_friend_id)
  order by s.score desc, e.start_datetime
  limit least(greatest(p_limit, 1), 30);
$$;

-- ---------------------------------------------------------------------------
-- 6: Kurzbewertungen
create table if not exists public.event_ratings (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, event_id)
);
alter table public.event_ratings enable row level security;
create policy "Eigene Bewertungen verwalten" on public.event_ratings for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Freunde sehen Bewertungen" on public.event_ratings for select using (are_friends(auth.uid(), user_id));

create or replace function public.rate_event(p_event_id uuid, p_stars int, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from events where id = p_event_id and start_datetime <= now()) then raise exception 'event not started'; end if;
  insert into event_ratings(user_id, event_id, stars, comment) values (auth.uid(), p_event_id, p_stars, nullif(trim(p_comment), ''))
  on conflict (user_id, event_id) do update set stars = excluded.stars, comment = excluded.comment, updated_at = now();
  -- Bewerten heißt: war dort.
  insert into event_attendance(user_id, event_id, attended_at, verification_type) values (auth.uid(), p_event_id, now(), 'manual')
  on conflict do nothing;
end; $$;

create or replace function public.event_ratings_summary(p_event_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'mine', (select jsonb_build_object('stars', stars, 'comment', comment) from event_ratings where user_id = auth.uid() and event_id = p_event_id),
    'friends', coalesce((select jsonb_agg(jsonb_build_object('user_id', r.user_id, 'display_name', coalesce(p.display_name, 'Freund:in'), 'avatar_url', p.avatar_url, 'stars', r.stars, 'comment', r.comment) order by r.updated_at desc)
      from event_ratings r left join profiles p on p.id = r.user_id where r.event_id = p_event_id and are_friends(auth.uid(), r.user_id)), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- 5: Freunde-Feed (nur Freunde mit share_activity; Zusagen, Besuche,
-- Bewertungen, Pläne – keine Merkliste "interessiert").
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
  order by i.happened_at desc
  limit least(greatest(p_limit, 1), 100);
$$;

-- ---------------------------------------------------------------------------
-- 9: Beliebt bei Freunden (mind. 2 Freunde haben gemerkt oder sagen zu)
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
  where f.user_id = auth.uid()
  group by e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1]
  having count(distinct fav.user_id) >= 2
  order by count(distinct fav.user_id) desc, e.start_datetime
  limit least(greatest(p_limit, 1), 30);
$$;

-- ---------------------------------------------------------------------------
-- 10: Gemeinsame Konzerte mit einem Freund in einem Jahr
create or replace function public.shared_concerts_with(p_friend_id uuid, p_year int)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text)
language sql stable security definer set search_path = public as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name
  from event_attendance a
  join event_attendance b on b.event_id = a.event_id and b.user_id = p_friend_id
  join events e on e.id = a.event_id
  left join venues v on v.id = e.venue_id
  where a.user_id = auth.uid() and are_friends(auth.uid(), p_friend_id)
    and extract(year from e.start_datetime at time zone 'Europe/Berlin') = p_year
  order by e.start_datetime;
$$;

-- ---------------------------------------------------------------------------
-- 7 + Benachrichtigungen: Warteschlange, die notify-social per Trigger
-- abarbeitet (pg_net, gleicher Weg wie die Cron-Jobs).
create table if not exists public.social_notifications (
  id bigint generated always as identity primary key,
  kind text not null,
  recipient uuid not null references auth.users(id) on delete cascade,
  actor uuid references auth.users(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  ref_id uuid,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
alter table public.social_notifications enable row level security;
create policy "Eigene Benachrichtigungen" on public.social_notifications for select using (recipient = auth.uid());
create index if not exists social_notifications_unsent on public.social_notifications (created_at) where sent_at is null;

create or replace function public.notify_social(p_kind text, p_recipient uuid, p_actor uuid, p_event_id uuid, p_ref uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if p_recipient is null or p_recipient = p_actor or is_blocked_between(p_recipient, p_actor) then return; end if;
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

-- 7: Wer "Ich gehe hin" wählt, informiert Freunde, die auch hingehen.
create or replace function public.favorites_attending_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_friend uuid;
begin
  if new.status = 'attending' and (tg_op = 'INSERT' or old.status is distinct from 'attending') then
    for v_friend in
      select f.friend_id from friendships f
      join favorites fav on fav.user_id = f.friend_id and fav.event_id = new.event_id and fav.status = 'attending'
      where f.user_id = new.user_id
    loop
      perform notify_social('friend_also_attending', v_friend, new.user_id, new.event_id, null);
    end loop;
  end if;
  return new;
end; $$;
drop trigger if exists favorites_attending_notify on public.favorites;
create trigger favorites_attending_notify after insert or update of status on public.favorites
  for each row execute function public.favorites_attending_notify();

-- ---------------------------------------------------------------------------
-- Rechte
do $$
declare f text;
begin
  foreach f in array array[
    'block_user(uuid)', 'unblock_user(uuid)', 'report_user(uuid,text,text)', 'send_friend_request(uuid,text)', 'respond_friend_request(uuid,boolean)',
    'cancel_friend_request(uuid)', 'my_friend_requests()', 'set_contact_discovery(boolean,text)', 'match_contacts(text[])',
    'suggested_friends(int)', 'search_profiles(text)', 'user_profile(uuid)', 'update_social_settings(text,boolean,boolean)',
    'my_social_settings()', 'create_concert_plan(uuid,uuid[],text,timestamptz,text)', 'respond_concert_plan(uuid,text)',
    'update_concert_plan(uuid,text,timestamptz,text)', 'leave_concert_plan(uuid)', 'invite_to_plan(uuid,uuid[])', 'my_concert_plans()',
    'share_list_with_friends(uuid,uuid[])', 'remove_list_member(uuid,uuid)', 'list_members(uuid)', 'lists_shared_with_me()',
    'friend_match_events(uuid,int)', 'rate_event(uuid,int,text)', 'event_ratings_summary(uuid)', 'friend_activity(int)',
    'friends_popular_events(int)', 'shared_concerts_with(uuid,int)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
