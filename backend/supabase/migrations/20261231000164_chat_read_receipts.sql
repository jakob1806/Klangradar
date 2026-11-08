-- Chat: Gelesen-Status (08.11.2026). chat_members_of liefert zusätzlich,
-- bis wann jedes Mitglied gelesen hat; die App zeigt daraus „Gesehen“.
drop function if exists public.chat_members_of(uuid);
create function public.chat_members_of(p_conversation uuid)
returns table (user_id uuid, display_name text, avatar_url text, last_read_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url, m.last_read_at
  from chat_members m join profiles p on p.id = m.user_id
  where m.conversation_id = p_conversation and is_chat_member(p_conversation)
  order by p.display_name;
$$;
grant execute on function public.chat_members_of(uuid) to authenticated;
