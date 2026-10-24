-- Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 9, 10, 12).
-- Hinweis: baut auf taste_signals() aus 000105 auf.

-- ---------------------------------------------------------------------------
-- 9: Abstimmung im Konzertplan. Ein Plan kann 2–3 Konzerte zur Wahl haben;
-- sobald alle Zugesagten abgestimmt haben (oder die erstellende Person
-- entscheidet), wird das Konzert mit den meisten Stimmen der Plan.
create table if not exists public.concert_plan_options (
  plan_id uuid not null references public.concert_plans(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  primary key (plan_id, event_id)
);
create table if not exists public.concert_plan_votes (
  plan_id uuid not null references public.concert_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  voted_at timestamptz not null default now(),
  primary key (plan_id, user_id)
);
alter table public.concert_plan_options enable row level security;
alter table public.concert_plan_votes enable row level security;
create policy "Mitglieder sehen Optionen" on public.concert_plan_options for select using (is_plan_member(plan_id));
create policy "Mitglieder sehen Stimmen" on public.concert_plan_votes for select using (is_plan_member(plan_id));

create or replace function public.create_plan_poll(p_event_ids uuid[], p_friend_ids uuid[], p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_plan uuid;
  v_event uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(array_length(p_event_ids, 1), 0) < 2 or array_length(p_event_ids, 1) > 3 then raise exception 'need 2-3 options'; end if;
  v_plan := create_concert_plan(p_event_ids[1], p_friend_ids, null, null, coalesce(nullif(trim(p_note), ''), 'Welches Konzert nehmen wir?'));
  foreach v_event in array p_event_ids loop
    insert into concert_plan_options(plan_id, event_id) values (v_plan, v_event) on conflict do nothing;
  end loop;
  return v_plan;
end; $$;

create or replace function public.decide_plan_poll(p_plan_id uuid, p_force boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_winner uuid;
  v_open int;
begin
  if not exists (select 1 from concert_plan_options where plan_id = p_plan_id) then return null; end if;
  select count(*) into v_open from concert_plan_members m
   where m.plan_id = p_plan_id and m.status <> 'declined'
     and not exists (select 1 from concert_plan_votes v where v.plan_id = p_plan_id and v.user_id = m.user_id);
  if v_open > 0 and not (p_force and exists (select 1 from concert_plans where id = p_plan_id and created_by = auth.uid())) then
    return null;
  end if;
  select o.event_id into v_winner
    from concert_plan_options o
    left join concert_plan_votes v on v.plan_id = o.plan_id and v.event_id = o.event_id
    join events e on e.id = o.event_id
   where o.plan_id = p_plan_id
   group by o.event_id, e.start_datetime
   order by count(v.user_id) desc, e.start_datetime
   limit 1;
  update concert_plans set event_id = v_winner where id = p_plan_id;
  delete from concert_plan_options where plan_id = p_plan_id;
  delete from concert_plan_votes where plan_id = p_plan_id;
  -- Zusagen gelten für das gewählte Konzert.
  insert into favorites(user_id, event_id, status)
    select m.user_id, v_winner, 'attending' from concert_plan_members m where m.plan_id = p_plan_id and m.status = 'going'
  on conflict (user_id, event_id) do update set status = 'attending';
  return v_winner;
end; $$;

create or replace function public.vote_plan_option(p_plan_id uuid, p_event_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  if not is_plan_member(p_plan_id) then raise exception 'not a member'; end if;
  if not exists (select 1 from concert_plan_options where plan_id = p_plan_id and event_id = p_event_id) then raise exception 'unknown option'; end if;
  insert into concert_plan_votes(plan_id, user_id, event_id) values (p_plan_id, auth.uid(), p_event_id)
  on conflict (plan_id, user_id) do update set event_id = excluded.event_id, voted_at = now();
  return decide_plan_poll(p_plan_id);
end; $$;

create or replace function public.plan_poll(p_plan_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not is_plan_member(p_plan_id) then '[]'::jsonb else coalesce(jsonb_agg(jsonb_build_object(
      'event_id', e.id, 'slug', e.slug, 'title', e.title, 'start_datetime', e.start_datetime,
      'venue_name', v.name, 'image_url', e.image_urls[1],
      'votes', (select count(*) from concert_plan_votes x where x.plan_id = o.plan_id and x.event_id = o.event_id),
      'mine', exists (select 1 from concert_plan_votes x where x.plan_id = o.plan_id and x.event_id = o.event_id and x.user_id = auth.uid())
    ) order by e.start_datetime), '[]'::jsonb) end
  from concert_plan_options o join events e on e.id = o.event_id left join venues v on v.id = e.venue_id
  where o.plan_id = p_plan_id
$$;

grant execute on function public.create_plan_poll(uuid[], uuid[], text) to authenticated;
grant execute on function public.vote_plan_option(uuid, uuid) to authenticated;
grant execute on function public.decide_plan_poll(uuid, boolean) to authenticated;
grant execute on function public.plan_poll(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10: Welche Freunde mögen, was in diesem Konzert spielt? Nur Freunde, die
-- Aktivität teilen; Begründung nennt die gemeinsame Vorliebe.
create or replace function public.friend_taste_for_event(p_event_id uuid)
returns table(user_id uuid, display_name text, avatar_url text, reason text)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  return query
  with friends as (
    select pr.id, pr.display_name, pr.avatar_url
      from profiles pr
     where pr.id <> auth.uid() and are_friends(auth.uid(), pr.id) and coalesce(pr.share_activity, true)
       and not is_blocked_between(auth.uid(), pr.id)
  ),
  event_composers as (
    select distinct wk.composer_id as id, p.full_name as name
      from event_works ew join works wk on wk.id = ew.work_id join persons p on p.id = wk.composer_id
     where ew.event_id = p_event_id
  ),
  event_artists as (
    select distinct coalesce(ep.person_id, ep.ensemble_id) as id, coalesce(pp.full_name, en.name) as name
      from event_participants ep left join persons pp on pp.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
     where ep.event_id = p_event_id
  ),
  matches as (
    select f.id as uid, f.display_name, f.avatar_url, ec.name, sum(sig.weight) as w
      from friends f
      cross join lateral taste_signals(f.id) sig
      join event_works ew on ew.event_id = sig.event_id join works wk on wk.id = ew.work_id
      join event_composers ec on ec.id = wk.composer_id
     group by f.id, f.display_name, f.avatar_url, ec.name
    union all
    select f.id, f.display_name, f.avatar_url, ea.name, sum(sig.weight) * 1.2
      from friends f
      cross join lateral taste_signals(f.id) sig
      join event_participants ep on ep.event_id = sig.event_id
      join event_artists ea on ea.id = coalesce(ep.person_id, ep.ensemble_id)
     group by f.id, f.display_name, f.avatar_url, ea.name
    union all
    select f.id, f.display_name, f.avatar_url, ea.name, 2.5
      from friends f join event_artists ea on true
     where exists (select 1 from user_favorite_persons u where u.user_id = f.id and u.person_id = ea.id)
        or exists (select 1 from user_favorite_ensembles u where u.user_id = f.id and u.ensemble_id = ea.id)
  ),
  best as (select distinct on (uid) uid, display_name, avatar_url, name, w from matches where w > 1 order by uid, w desc)
  select b.uid, coalesce(b.display_name, 'Freund:in'), b.avatar_url, 'mag auch ' || b.name
    from best b order by b.w desc limit 5;
end; $$;
grant execute on function public.friend_taste_for_event(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 12: Dein Konzertjahr.
create or replace function public.my_concert_year(p_year int default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_year int := coalesce(p_year, extract(year from now())::int);
  v_from timestamptz := make_timestamptz(v_year, 1, 1, 0, 0, 0, 'Europe/Berlin');
  v_to timestamptz := make_timestamptz(v_year + 1, 1, 1, 0, 0, 0, 'Europe/Berlin');
  v_result jsonb;
begin
  if auth.uid() is null then return '{}'::jsonb; end if;
  with attended as (
    select e.id, e.slug, e.title, e.start_datetime, e.end_datetime, e.duration_minutes, e.venue_id from events e
     where e.start_datetime >= v_from and e.start_datetime < v_to and e.start_datetime <= now()
       and (exists (select 1 from event_attendance a where a.event_id = e.id and a.user_id = auth.uid())
            or exists (select 1 from event_ratings r where r.event_id = e.id and r.user_id = auth.uid())
            or exists (select 1 from favorites f where f.event_id = e.id and f.user_id = auth.uid() and f.status = 'attending'))
  )
  select jsonb_build_object(
    'year', v_year,
    'concerts', (select count(*) from attended),
    'minutes', (select coalesce(sum(coalesce(duration_minutes, extract(epoch from (end_datetime - start_datetime)) / 60, 120)), 0)::int from attended),
    'venues', (select count(distinct venue_id) from attended),
    'top_composers', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'count', c)) from (
        select p.full_name name, count(distinct a.id) c from attended a join event_works ew on ew.event_id = a.id
          join works wk on wk.id = ew.work_id join persons p on p.id = wk.composer_id
         group by p.full_name order by c desc, p.full_name limit 3) t), '[]'),
    'top_venue', (select v.name from attended a join venues v on v.id = a.venue_id group by v.name order by count(*) desc limit 1),
    'top_artist', (select coalesce(pp.full_name, en.name) from attended a join event_participants ep on ep.event_id = a.id
                     left join persons pp on pp.id = ep.person_id left join ensembles en on en.id = ep.ensemble_id
                    group by 1 order by count(*) desc limit 1),
    'best_rated', (select jsonb_build_object('title', e.title, 'stars', r.stars, 'slug', e.slug) from event_ratings r join attended e on e.id = r.event_id
                    where r.user_id = auth.uid() order by r.stars desc, e.start_datetime desc limit 1),
    'first', (select jsonb_build_object('title', title, 'date', start_datetime) from attended order by start_datetime limit 1)
  ) into v_result;
  return v_result;
end; $$;
grant execute on function public.my_concert_year(int) to authenticated;
