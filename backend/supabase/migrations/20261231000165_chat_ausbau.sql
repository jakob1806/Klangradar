-- Chat-Ausbau (09.11.2026): Antworten auf Nachrichten, Fotos, „schreibt …“.
alter table public.chat_messages add column if not exists reply_to uuid references public.chat_messages(id) on delete set null;
alter table public.chat_messages add column if not exists image_path text check (image_path is null or char_length(image_path) <= 300);
alter table public.chat_messages drop constraint if exists chat_messages_kind_check;
alter table public.chat_messages add constraint chat_messages_kind_check check (kind in ('text', 'event', 'invite', 'system', 'image'));
alter table public.chat_members add column if not exists typing_until timestamptz;

-- Fotos: privater Bucket, Ordner = Gespräch; lesen/hochladen nur Mitglieder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-images', 'chat-images', false, 4194304, array['image/jpeg'])
on conflict (id) do nothing;
-- Sicher auch bei fremden Pfaden (kein Fehler durch uuid-Umwandlung).
create or replace function public.chat_image_access(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then is_chat_member(split_part(p_name, '/', 1)::uuid) else false end;
$$;
grant execute on function public.chat_image_access(text) to authenticated;

drop policy if exists "Chatfotos lesen" on storage.objects;
create policy "Chatfotos lesen" on storage.objects for select
  using (bucket_id = 'chat-images' and public.chat_image_access(name));
drop policy if exists "Chatfotos hochladen" on storage.objects;
create policy "Chatfotos hochladen" on storage.objects for insert
  with check (bucket_id = 'chat-images' and public.chat_image_access(name));

drop function if exists public.chat_send(uuid, text, text, uuid);
create function public.chat_send(p_conversation uuid, p_kind text, p_body text, p_event_id uuid default null,
                                 p_reply_to uuid default null, p_image_path text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_member record;
begin
  if not is_chat_member(p_conversation) then raise exception 'not_member'; end if;
  if p_kind not in ('text', 'event', 'invite', 'image') then raise exception 'invalid_kind'; end if;
  if p_kind = 'text' and coalesce(btrim(p_body), '') = '' then raise exception 'empty'; end if;
  if p_kind in ('event', 'invite') and p_event_id is null then raise exception 'event_required'; end if;
  if p_kind = 'image' and (p_image_path is null or split_part(p_image_path, '/', 1) <> p_conversation::text) then
    raise exception 'image_required';
  end if;
  if p_reply_to is not null and not exists (select 1 from chat_messages where id = p_reply_to and conversation_id = p_conversation) then
    p_reply_to := null;
  end if;
  insert into chat_messages (conversation_id, sender_id, kind, body, event_id, reply_to, image_path)
  values (p_conversation, auth.uid(), p_kind, nullif(btrim(coalesce(p_body, '')), ''), p_event_id, p_reply_to,
          case when p_kind = 'image' then p_image_path end)
  returning id into v_id;
  update chat_conversations set last_message_at = now() where id = p_conversation;
  update chat_members set last_read_at = now(), typing_until = null where conversation_id = p_conversation and user_id = auth.uid();
  for v_member in
    select user_id from chat_members
    where conversation_id = p_conversation and user_id <> auth.uid() and not muted
  loop
    perform notify_chat(v_member.user_id, auth.uid(), v_id, p_event_id);
  end loop;
  return v_id;
end; $$;
grant execute on function public.chat_send(uuid, text, text, uuid, uuid, text) to authenticated;

create or replace function public.chat_typing(p_conversation uuid)
returns void language sql security definer set search_path = public as $$
  update chat_members set typing_until = now() + interval '6 seconds'
  where conversation_id = p_conversation and user_id = auth.uid();
$$;
grant execute on function public.chat_typing(uuid) to authenticated;

drop function if exists public.chat_thread(uuid, timestamptz, integer);
create function public.chat_thread(p_conversation uuid, p_before timestamptz default null, p_limit integer default 60)
returns table (id uuid, sender_id uuid, sender_name text, sender_avatar text, kind text, body text, created_at timestamptz,
               deleted boolean, event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text,
               image_url text, reactions jsonb, reply_to uuid, reply_body text, reply_sender text, image_path text)
language sql stable security definer set search_path = public as $$
  select m.id, m.sender_id, p.display_name, p.avatar_url, m.kind, m.body, m.created_at, m.deleted_at is not null,
         e.id, e.slug, e.title, e.start_datetime, v.name, coalesce(e.image_urls[1], v.photo_url),
         coalesce((select jsonb_agg(jsonb_build_object('user_id', r.user_id, 'emoji', r.emoji)) from chat_reactions r where r.message_id = m.id), '[]'::jsonb),
         m.reply_to,
         case when rm.deleted_at is not null then 'Nachricht gelöscht'
              when rm.kind = 'image' then coalesce('📷 ' || rm.body, '📷 Foto')
              when rm.kind in ('event', 'invite') then coalesce(re.title, 'Konzert')
              else left(rm.body, 160) end,
         rp.display_name,
         case when m.deleted_at is null then m.image_path end
  from chat_messages m
  left join profiles p on p.id = m.sender_id
  left join events e on e.id = m.event_id
  left join venues v on v.id = e.venue_id
  left join chat_messages rm on rm.id = m.reply_to
  left join events re on re.id = rm.event_id
  left join profiles rp on rp.id = rm.sender_id
  where m.conversation_id = p_conversation and is_chat_member(p_conversation)
    and (p_before is null or m.created_at < p_before)
  order by m.created_at desc
  limit least(greatest(coalesce(p_limit, 60), 1), 200);
$$;
grant execute on function public.chat_thread(uuid, timestamptz, integer) to authenticated;

drop function if exists public.chat_members_of(uuid);
create function public.chat_members_of(p_conversation uuid)
returns table (user_id uuid, display_name text, avatar_url text, last_read_at timestamptz, typing boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url, m.last_read_at, coalesce(m.typing_until > now(), false)
  from chat_members m join profiles p on p.id = m.user_id
  where m.conversation_id = p_conversation and is_chat_member(p_conversation)
  order by p.display_name;
$$;
grant execute on function public.chat_members_of(uuid) to authenticated;
