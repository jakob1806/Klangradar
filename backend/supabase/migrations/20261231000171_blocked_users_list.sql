-- Erstellt von Claude Code (12.11.2026): Liste der von mir blockierten
-- Personen, damit man Blockierungen in der App wieder aufheben kann.
create or replace function public.my_blocked_users()
returns table (user_id uuid, display_name text, avatar_url text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select b.blocked_id, p.display_name, p.avatar_url, b.created_at
  from user_blocks b
  left join profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;
revoke all on function public.my_blocked_users() from public, anon;
grant execute on function public.my_blocked_users() to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
