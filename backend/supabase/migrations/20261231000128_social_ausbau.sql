-- Erstellt von Claude Code (Nutzerwunsch 28.10.2026: "kannst alles bauen"):
-- Social-Ausbau in fünf Teilen.
--   1. "Ich komme mit": einem Freund zu seinem Konzert folgen (Plan anlegen
--      oder beitreten, Freund bekommt Bescheid).
--   2. Nachklang: Applaus und Kommentare zu Bewertungen von Freunden.
--   3. Konzert-Buddys: Freunde, die zu deinen gemerkten Konzerten passen.
--   4. Euer Jahr: gemeinsamer Jahresrückblick mit einem Freund.
--   5. Gruppen: Freundeskreise (z. B. "Chor", "Abo-Nachbarn") mit
--      gemeinsamer Konzertübersicht und Gruppen-Einladung.
-- Alles nur zwischen Freunden; Sperren (is_blocked_between) gelten überall.

-- ---------------------------------------------------------------------------
-- 1. Ich komme mit
create or replace function public.join_friend_concert(p_event_id uuid, p_friend_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_plan uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not are_friends(auth.uid(), p_friend_id) or is_blocked_between(auth.uid(), p_friend_id) then raise exception 'not friends'; end if;
  if not exists (select 1 from events where id = p_event_id and start_datetime > now()) then raise exception 'event not upcoming'; end if;

  -- Gibt es schon einen Plan mit dem Freund für dieses Konzert? Dann beitreten.
  select p.id into v_plan
  from concert_plans p
  join concert_plan_members m on m.plan_id = p.id and m.user_id = p_friend_id and m.status <> 'declined'
  where p.event_id = p_event_id
  order by (p.created_by = p_friend_id) desc, p.created_at
  limit 1;

  if v_plan is null then
    insert into concert_plans(event_id, created_by, note) values (p_event_id, auth.uid(), null) returning id into v_plan;
    insert into concert_plan_members(plan_id, user_id, status, responded_at) values (v_plan, p_friend_id, 'going', now())
      on conflict do nothing;
  end if;
  insert into concert_plan_members(plan_id, user_id, status, responded_at) values (v_plan, auth.uid(), 'going', now())
    on conflict (plan_id, user_id) do update set status = 'going', responded_at = now();
  perform mark_attending(auth.uid(), p_event_id);
  perform notify_social('joins_you', p_friend_id, auth.uid(), p_event_id, v_plan);
  return v_plan;
end; $$;

-- ---------------------------------------------------------------------------
-- 2. Applaus und Kommentare zu Bewertungen
create table if not exists public.rating_reactions (
  id uuid primary key default gen_random_uuid(),
  rating_user uuid not null,
  event_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('applause', 'comment')),
  body text check (body is null or char_length(body) between 1 and 300),
  created_at timestamptz not null default now(),
  foreign key (rating_user, event_id) references public.event_ratings(user_id, event_id) on delete cascade,
  check ((kind = 'comment') = (body is not null))
);
create unique index if not exists rating_reactions_one_applause on public.rating_reactions (rating_user, event_id, user_id) where kind = 'applause';
create index if not exists rating_reactions_rating_idx on public.rating_reactions (rating_user, event_id);
alter table public.rating_reactions enable row level security;
-- Zugriff nur über die Funktionen unten.

create or replace function public.can_see_rating(p_rating_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() = p_rating_user
    or (are_friends(auth.uid(), p_rating_user) and not is_blocked_between(auth.uid(), p_rating_user));
$$;

create or replace function public.toggle_rating_applause(p_rating_user uuid, p_event_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not can_see_rating(p_rating_user) then raise exception 'not allowed'; end if;
  if exists (select 1 from rating_reactions where rating_user = p_rating_user and event_id = p_event_id and user_id = auth.uid() and kind = 'applause') then
    delete from rating_reactions where rating_user = p_rating_user and event_id = p_event_id and user_id = auth.uid() and kind = 'applause';
    return false;
  end if;
  insert into rating_reactions(rating_user, event_id, user_id, kind) values (p_rating_user, p_event_id, auth.uid(), 'applause');
  perform notify_social('rating_applause', p_rating_user, auth.uid(), p_event_id, null);
  return true;
end; $$;

create or replace function public.comment_on_rating(p_rating_user uuid, p_event_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null or not can_see_rating(p_rating_user) then raise exception 'not allowed'; end if;
  if nullif(trim(p_body), '') is null then raise exception 'empty'; end if;
  insert into rating_reactions(rating_user, event_id, user_id, kind, body)
    values (p_rating_user, p_event_id, auth.uid(), 'comment', left(trim(p_body), 300)) returning id into v_id;
  perform notify_social('rating_comment', p_rating_user, auth.uid(), p_event_id, v_id);
  return v_id;
end; $$;

-- Eigene Kommentare und Kommentare unter der eigenen Bewertung löschbar.
create or replace function public.delete_rating_comment(p_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from rating_reactions where id = p_id and kind = 'comment' and (user_id = auth.uid() or rating_user = auth.uid());
$$;

-- Nachklang: Bewertungen von Freunden (und eigene) mit Applaus und Kommentaren.
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
      and (r.user_id = auth.uid() or (r.user_id in (select friend_id from friendships where user_id = auth.uid()) and p.share_activity))
      and not is_blocked_between(auth.uid(), r.user_id)
    order by r.updated_at desc
    limit least(greatest(p_limit, 1), 50)
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- 3. Konzert-Buddys: zu meinen kommenden gemerkten Konzerten passende Freunde,
--    mit denen es noch keinen gemeinsamen Plan gibt.
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
    -- hat dasselbe Konzert gemerkt
    select m.event_id, fr.id as friend_id, 'Hat es sich auch gemerkt' as reason, 3 as score
    from mine m join favorites ff on ff.event_id = m.event_id join friends fr on fr.id = ff.user_id
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
      where a.user_id = fr.id and w2.composer_id = c.id)
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

-- ---------------------------------------------------------------------------
-- 4. Euer Jahr: gemeinsame Konzerte (beide besucht) eines Jahres.
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
        and e.start_datetime <= now()
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
                   where a.user_id = auth.uid() and a.status = 'attending' and b.status = 'attending')
    )
  );
end; $$;

-- ---------------------------------------------------------------------------
-- 5. Gruppen
create table if not exists public.social_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 40),
  emoji text check (emoji is null or char_length(emoji) <= 4),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.social_group_members (
  group_id uuid not null references public.social_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  added_by uuid references auth.users(id) on delete set null,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists social_group_members_user_idx on public.social_group_members (user_id);
alter table public.social_groups enable row level security;
alter table public.social_group_members enable row level security;
-- Zugriff nur über die Funktionen unten.

create or replace function public.is_group_member(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from social_group_members where group_id = p_group and user_id = auth.uid());
$$;

create or replace function public.add_social_group_members(p_group_id uuid, p_member_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_added int := 0;
begin
  if not is_group_member(p_group_id) then raise exception 'not allowed'; end if;
  foreach v_id in array coalesce(p_member_ids, '{}') loop
    -- Nur eigene Freunde hinzufügen.
    if are_friends(auth.uid(), v_id) and not is_blocked_between(auth.uid(), v_id) then
      insert into social_group_members(group_id, user_id, added_by) values (p_group_id, v_id, auth.uid()) on conflict do nothing;
      if found then
        v_added := v_added + 1;
        perform notify_social('group_added', v_id, auth.uid(), null, p_group_id);
      end if;
    end if;
  end loop;
  return v_added;
end; $$;

create or replace function public.create_social_group(p_name text, p_emoji text, p_member_ids uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare v_group uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into social_groups(name, emoji, created_by) values (trim(p_name), nullif(trim(p_emoji), ''), auth.uid()) returning id into v_group;
  insert into social_group_members(group_id, user_id, added_by) values (v_group, auth.uid(), auth.uid());
  perform add_social_group_members(v_group, p_member_ids);
  return v_group;
end; $$;

create or replace function public.update_social_group(p_group_id uuid, p_name text, p_emoji text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_group_member(p_group_id) then raise exception 'not allowed'; end if;
  update social_groups set name = trim(p_name), emoji = nullif(trim(p_emoji), '') where id = p_group_id;
end; $$;

create or replace function public.leave_social_group(p_group_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from social_group_members where group_id = p_group_id and user_id = auth.uid();
  delete from social_groups g where g.id = p_group_id and not exists (select 1 from social_group_members m where m.group_id = g.id);
end; $$;

-- Meine Gruppen mit Mitgliedern (Gesperrte ausgeblendet).
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
                   where m.group_id = g.id)
    ) order by g.created_at desc), '[]'::jsonb)
  from social_groups g
  where is_group_member(g.id);
$$;

-- Wohin die Gruppe geht: kommende Konzerte, zu denen Mitglieder zugesagt
-- haben (nur Mitglieder mit geteilter Aktivität).
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
  group by e.id, e.slug, e.title, e.start_datetime, v.name, e.image_urls[1]
  order by e.start_datetime
  limit 40;
$$;

-- ---------------------------------------------------------------------------
-- Rechte
do $$
declare f text;
begin
  foreach f in array array[
    'join_friend_concert(uuid,uuid)', 'toggle_rating_applause(uuid,uuid)', 'comment_on_rating(uuid,uuid,text)',
    'delete_rating_comment(uuid)', 'friend_echoes(int)', 'concert_buddy_suggestions(int)', 'shared_year_with(uuid,int)',
    'create_social_group(text,text,uuid[])', 'add_social_group_members(uuid,uuid[])', 'update_social_group(uuid,text,text)',
    'leave_social_group(uuid)', 'my_social_groups()', 'social_group_concerts(uuid)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['can_see_rating(uuid)', 'is_group_member(uuid)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
