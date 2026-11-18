-- Erstellt von Claude Code (18.11.2026): Gemeinsamer Abend – im Konzertplan
-- Restaurants vorschlagen und abstimmen (eine Stimme pro Person).
create table if not exists public.concert_plan_restaurants (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references concert_plans(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 160),
  address text check (address is null or char_length(address) <= 300),
  lat double precision,
  lng double precision,
  added_by uuid not null references auth.users(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  unique (plan_id, name)
);
create table if not exists public.concert_plan_restaurant_votes (
  plan_id uuid not null references concert_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  restaurant_id uuid not null references concert_plan_restaurants(id) on delete cascade,
  voted_at timestamptz not null default now(),
  primary key (plan_id, user_id)
);
alter table public.concert_plan_restaurants enable row level security;
alter table public.concert_plan_restaurant_votes enable row level security;
create policy "Mitglieder sehen Restaurants" on public.concert_plan_restaurants for select using (is_plan_member(plan_id));
create policy "Mitglieder sehen Restaurant-Stimmen" on public.concert_plan_restaurant_votes for select using (is_plan_member(plan_id));

create or replace function public.add_plan_restaurant(p_plan_id uuid, p_name text, p_address text default null, p_lat double precision default null, p_lng double precision default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_plan_member(p_plan_id) then raise exception 'not a member'; end if;
  insert into concert_plan_restaurants(plan_id, name, address, lat, lng, added_by)
  values (p_plan_id, left(btrim(p_name), 160), left(p_address, 300), p_lat, p_lng, auth.uid())
  on conflict (plan_id, name) do update set address = coalesce(excluded.address, concert_plan_restaurants.address)
  returning id into v_id;
  insert into concert_plan_restaurant_votes(plan_id, user_id, restaurant_id) values (p_plan_id, auth.uid(), v_id)
  on conflict (plan_id, user_id) do update set restaurant_id = excluded.restaurant_id, voted_at = now();
  return v_id;
end; $$;

create or replace function public.vote_plan_restaurant(p_plan_id uuid, p_restaurant_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_plan_member(p_plan_id) then raise exception 'not a member'; end if;
  if not exists (select 1 from concert_plan_restaurants where id = p_restaurant_id and plan_id = p_plan_id) then raise exception 'unknown option'; end if;
  insert into concert_plan_restaurant_votes(plan_id, user_id, restaurant_id) values (p_plan_id, auth.uid(), p_restaurant_id)
  on conflict (plan_id, user_id) do update set restaurant_id = excluded.restaurant_id, voted_at = now();
end; $$;

create or replace function public.plan_restaurants(p_plan_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not is_plan_member(p_plan_id) then '[]'::jsonb else coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'name', r.name, 'address', r.address, 'lat', r.lat, 'lng', r.lng,
    'votes', (select count(*) from concert_plan_restaurant_votes v where v.restaurant_id = r.id),
    'mine', exists (select 1 from concert_plan_restaurant_votes v where v.restaurant_id = r.id and v.user_id = auth.uid())
  ) order by (select count(*) from concert_plan_restaurant_votes v where v.restaurant_id = r.id) desc, r.created_at), '[]'::jsonb) end
  from concert_plan_restaurants r where r.plan_id = p_plan_id;
$$;
grant execute on function public.add_plan_restaurant(uuid, text, text, double precision, double precision) to authenticated;
grant execute on function public.vote_plan_restaurant(uuid, uuid) to authenticated;
grant execute on function public.plan_restaurants(uuid) to authenticated;
