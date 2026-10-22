-- Erstellt von Claude Code ("Mit Freunden", Punkt 7 der Ausbauliste).
-- Freundschaft per persönlichem Code: Wer seinen Code teilt, willigt ein.
-- Freunde sehen gegenseitig nur, zu welchen kommenden Konzerten man
-- "hingeht" (favorites.status = 'attending'), keine Merkliste, keine Historie.

create table if not exists public.friend_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now()
);
alter table public.friend_codes enable row level security;
create policy "Eigenen Code lesen" on public.friend_codes for select using (user_id = auth.uid());

create table if not exists public.friendships (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
alter table public.friendships enable row level security;
create policy "Eigene Freundschaften lesen" on public.friendships for select using (user_id = auth.uid());

-- Eigener Code, wird beim ersten Aufruf erzeugt (8 Zeichen, ohne 0/O/1/I).
create or replace function public.my_friend_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select code into v_code from friend_codes where user_id = auth.uid();
  if v_code is not null then return v_code; end if;
  loop
    v_code := '';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    begin
      insert into friend_codes(user_id, code) values (auth.uid(), v_code);
      return v_code;
    exception when unique_violation then
      -- Kollision: neuer Versuch (oder parallel bereits angelegt).
      select code into v_code from friend_codes where user_id = auth.uid();
      if v_code is not null then return v_code; end if;
    end;
  end loop;
end;
$$;

create or replace function public.add_friend_by_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_friend uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select user_id into v_friend from friend_codes where code = upper(trim(p_code));
  if v_friend is null then return jsonb_build_object('ok', false, 'reason', 'unknown_code'); end if;
  if v_friend = auth.uid() then return jsonb_build_object('ok', false, 'reason', 'own_code'); end if;
  insert into friendships(user_id, friend_id) values (auth.uid(), v_friend), (v_friend, auth.uid()) on conflict do nothing;
  return jsonb_build_object('ok', true, 'friend_id', v_friend,
    'display_name', (select display_name from profiles where id = v_friend));
end;
$$;

create or replace function public.remove_friend(p_friend_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from friendships
  where (user_id = auth.uid() and friend_id = p_friend_id) or (user_id = p_friend_id and friend_id = auth.uid());
$$;

create or replace function public.my_friends()
returns table (friend_id uuid, display_name text, avatar_url text, upcoming_count bigint)
language sql
stable
security definer
set search_path = public
as $$
  select f.friend_id, p.display_name, p.avatar_url,
    (select count(*) from favorites fav join events e on e.id = fav.event_id
      where fav.user_id = f.friend_id and fav.status = 'attending' and e.start_datetime >= now())
  from friendships f
  left join profiles p on p.id = f.friend_id
  where f.user_id = auth.uid()
  order by p.display_name nulls last;
$$;

-- Kommende Konzerte, zu denen Freunde gehen (für "Was deine Freunde vorhaben").
create or replace function public.friends_upcoming_events(p_limit int default 30)
returns table (event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text, friend_names text[])
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.slug, e.title, e.start_datetime, v.name,
    array_agg(coalesce(p.display_name, 'Freund:in') order by p.display_name)
  from friendships f
  join favorites fav on fav.user_id = f.friend_id and fav.status = 'attending'
  join events e on e.id = fav.event_id and e.start_datetime >= now() and e.status <> 'draft'
  left join venues v on v.id = e.venue_id
  left join profiles p on p.id = f.friend_id
  where f.user_id = auth.uid()
  group by e.id, e.slug, e.title, e.start_datetime, v.name
  order by e.start_datetime
  limit least(greatest(p_limit, 1), 100);
$$;

-- Freunde, die zu einem bestimmten Konzert gehen (Konzertseite).
create or replace function public.friends_attending(p_event_id uuid)
returns table (friend_id uuid, display_name text, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select f.friend_id, p.display_name, p.avatar_url
  from friendships f
  join favorites fav on fav.user_id = f.friend_id and fav.event_id = p_event_id and fav.status = 'attending'
  left join profiles p on p.id = f.friend_id
  where f.user_id = auth.uid();
$$;

revoke all on function public.my_friend_code(), public.add_friend_by_code(text), public.remove_friend(uuid),
  public.my_friends(), public.friends_upcoming_events(int), public.friends_attending(uuid) from public, anon;
grant execute on function public.my_friend_code(), public.add_friend_by_code(text), public.remove_friend(uuid),
  public.my_friends(), public.friends_upcoming_events(int), public.friends_attending(uuid) to authenticated;
