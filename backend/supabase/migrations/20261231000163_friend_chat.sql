-- Chat zwischen Freunden (Nutzerwunsch 08.11.2026, „fast wie WhatsApp“):
-- Einzel- und Gruppenchats, Textnachrichten, geteilte Konzerte,
-- Einladungen, Reaktionen, gelesen-Status, Push über notify-social.
-- Nur Freunde können einen Chat beginnen oder jemanden zu einer Gruppe
-- hinzufügen; Blockieren beendet die Zustellung.

create table if not exists public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text check (title is null or char_length(title) <= 60),
  icon text check (icon is null or char_length(icon) <= 40),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

create table if not exists public.chat_members (
  conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  muted boolean not null default false,
  primary key (conversation_id, user_id)
);
create index if not exists chat_members_user on public.chat_members (user_id);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.chat_conversations(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  kind text not null default 'text' check (kind in ('text', 'event', 'invite', 'system')),
  body text check (body is null or char_length(body) <= 4000),
  event_id uuid references public.events(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists chat_messages_conv_time on public.chat_messages (conversation_id, created_at desc);

create table if not exists public.chat_reactions (
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('👏', '❤️', '😂', '😮', '👍', '🎻')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.chat_conversations enable row level security;
alter table public.chat_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_reactions enable row level security;

create or replace function public.is_chat_member(p_conversation uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_members where conversation_id = p_conversation and user_id = auth.uid());
$$;

create policy "Mitglieder lesen Chats" on public.chat_conversations for select using (is_chat_member(id));
create policy "Mitglieder lesen Mitglieder" on public.chat_members for select using (is_chat_member(conversation_id));
create policy "Mitglieder lesen Nachrichten" on public.chat_messages for select using (is_chat_member(conversation_id));
create policy "Mitglieder lesen Reaktionen" on public.chat_reactions for select
  using (exists (select 1 from chat_messages m where m.id = message_id and is_chat_member(m.conversation_id)));
-- Schreiben ausschließlich über die Funktionen unten.

-- Einzelchat öffnen (oder bestehenden zurückgeben) --------------------------
create or replace function public.chat_open_direct(p_friend uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null or p_friend = auth.uid() then raise exception 'invalid'; end if;
  if not are_friends(auth.uid(), p_friend) then raise exception 'not_friends'; end if;
  select c.id into v_id from chat_conversations c
  where not c.is_group
    and exists (select 1 from chat_members where conversation_id = c.id and user_id = auth.uid())
    and exists (select 1 from chat_members where conversation_id = c.id and user_id = p_friend)
  limit 1;
  if v_id is not null then return v_id; end if;
  insert into chat_conversations (is_group, created_by) values (false, auth.uid()) returning id into v_id;
  insert into chat_members (conversation_id, user_id) values (v_id, auth.uid()), (v_id, p_friend);
  return v_id;
end; $$;

-- Gruppe erstellen -------------------------------------------------------------
create or replace function public.chat_create_group(p_title text, p_members uuid[], p_icon text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_member uuid;
begin
  if auth.uid() is null then raise exception 'invalid'; end if;
  if coalesce(btrim(p_title), '') = '' then raise exception 'title_required'; end if;
  insert into chat_conversations (is_group, title, icon, created_by)
  values (true, left(btrim(p_title), 60), p_icon, auth.uid()) returning id into v_id;
  insert into chat_members (conversation_id, user_id) values (v_id, auth.uid());
  foreach v_member in array coalesce(p_members, '{}') loop
    if v_member <> auth.uid() and are_friends(auth.uid(), v_member) then
      insert into chat_members (conversation_id, user_id) values (v_id, v_member) on conflict do nothing;
    end if;
  end loop;
  insert into chat_messages (conversation_id, sender_id, kind, body)
  values (v_id, auth.uid(), 'system', 'hat die Gruppe erstellt');
  return v_id;
end; $$;

create or replace function public.chat_add_members(p_conversation uuid, p_members uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_member uuid;
begin
  if not is_chat_member(p_conversation) then raise exception 'not_member'; end if;
  if not exists (select 1 from chat_conversations where id = p_conversation and is_group) then raise exception 'not_group'; end if;
  foreach v_member in array coalesce(p_members, '{}') loop
    if are_friends(auth.uid(), v_member) then
      insert into chat_members (conversation_id, user_id) values (p_conversation, v_member) on conflict do nothing;
    end if;
  end loop;
end; $$;

create or replace function public.chat_leave(p_conversation uuid)
returns void language sql security definer set search_path = public as $$
  delete from chat_members where conversation_id = p_conversation and user_id = auth.uid();
$$;

create or replace function public.chat_set_muted(p_conversation uuid, p_muted boolean)
returns void language sql security definer set search_path = public as $$
  update chat_members set muted = p_muted where conversation_id = p_conversation and user_id = auth.uid();
$$;

-- Nachricht senden ---------------------------------------------------------------
create or replace function public.chat_send(p_conversation uuid, p_kind text, p_body text, p_event_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_member record;
begin
  if not is_chat_member(p_conversation) then raise exception 'not_member'; end if;
  if p_kind not in ('text', 'event', 'invite') then raise exception 'invalid_kind'; end if;
  if p_kind = 'text' and coalesce(btrim(p_body), '') = '' then raise exception 'empty'; end if;
  if p_kind in ('event', 'invite') and p_event_id is null then raise exception 'event_required'; end if;
  insert into chat_messages (conversation_id, sender_id, kind, body, event_id)
  values (p_conversation, auth.uid(), p_kind, nullif(btrim(coalesce(p_body, '')), ''), p_event_id)
  returning id into v_id;
  update chat_conversations set last_message_at = now() where id = p_conversation;
  update chat_members set last_read_at = now() where conversation_id = p_conversation and user_id = auth.uid();
  for v_member in
    select user_id from chat_members
    where conversation_id = p_conversation and user_id <> auth.uid() and not muted
  loop
    perform notify_chat(v_member.user_id, auth.uid(), v_id, p_event_id);
  end loop;
  return v_id;
end; $$;

-- Push: eigener Weg ohne die Tagesbegrenzung von notify_social.
create or replace function public.notify_chat(p_recipient uuid, p_actor uuid, p_message uuid, p_event_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if p_recipient is null or p_recipient = p_actor or is_blocked_between(p_recipient, p_actor) then return; end if;
  insert into social_notifications(kind, recipient, actor, event_id, ref_id) values ('chat_message', p_recipient, p_actor, p_event_id, p_message);
  begin
    perform net.http_post(
      url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/notify-social',
      body := '{}'::jsonb,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', internal_function_secret(),
        'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
      timeout_milliseconds := 10000);
  exception when others then
    raise warning 'notify_chat: % (%)', sqlerrm, sqlstate;
  end;
end; $$;
revoke all on function public.notify_chat(uuid, uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.chat_mark_read(p_conversation uuid)
returns void language sql security definer set search_path = public as $$
  update chat_members set last_read_at = now() where conversation_id = p_conversation and user_id = auth.uid();
$$;

create or replace function public.chat_react(p_message uuid, p_emoji text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from chat_messages m where m.id = p_message and is_chat_member(m.conversation_id)) then raise exception 'not_member'; end if;
  if p_emoji is null then
    delete from chat_reactions where message_id = p_message and user_id = auth.uid();
  else
    insert into chat_reactions (message_id, user_id, emoji) values (p_message, auth.uid(), p_emoji)
    on conflict (message_id, user_id) do update set emoji = excluded.emoji, created_at = now();
  end if;
end; $$;

create or replace function public.chat_delete_message(p_message uuid)
returns void language sql security definer set search_path = public as $$
  update chat_messages set deleted_at = now(), body = null where id = p_message and sender_id = auth.uid();
$$;

-- Übersicht --------------------------------------------------------------------
create or replace function public.chat_inbox()
returns table (conversation_id uuid, is_group boolean, title text, icon text, other_user_id uuid,
               avatar_url text, last_body text, last_kind text, last_sender_name text, last_at timestamptz,
               unread integer, muted boolean, member_count integer)
language sql stable security definer set search_path = public as $$
  select c.id, c.is_group,
         case when c.is_group then c.title else op.display_name end,
         c.icon,
         case when c.is_group then null else o.user_id end,
         case when c.is_group then null else op.avatar_url end,
         lm.body, lm.kind, sp.display_name, coalesce(lm.created_at, c.created_at),
         (select count(*)::int from chat_messages x where x.conversation_id = c.id and x.created_at > me.last_read_at and x.sender_id is distinct from auth.uid() and x.deleted_at is null),
         me.muted,
         (select count(*)::int from chat_members mm where mm.conversation_id = c.id)
  from chat_members me
  join chat_conversations c on c.id = me.conversation_id
  left join lateral (select user_id from chat_members where conversation_id = c.id and user_id <> auth.uid() limit 1) o on not c.is_group
  left join profiles op on op.id = o.user_id
  left join lateral (select * from chat_messages where conversation_id = c.id and deleted_at is null order by created_at desc limit 1) lm on true
  left join profiles sp on sp.id = lm.sender_id
  where me.user_id = auth.uid()
    and (c.is_group or o.user_id is null or not is_blocked_between(auth.uid(), o.user_id))
  order by coalesce(lm.created_at, c.created_at) desc;
$$;

create or replace function public.chat_unread_total()
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(sum((select count(*) from chat_messages x where x.conversation_id = me.conversation_id
         and x.created_at > me.last_read_at and x.sender_id is distinct from auth.uid() and x.deleted_at is null)), 0)::int
  from chat_members me where me.user_id = auth.uid() and not me.muted;
$$;

-- Verlauf mit Absender, Konzert und Reaktionen -----------------------------------
create or replace function public.chat_thread(p_conversation uuid, p_before timestamptz default null, p_limit integer default 60)
returns table (id uuid, sender_id uuid, sender_name text, sender_avatar text, kind text, body text, created_at timestamptz,
               deleted boolean, event_id uuid, slug text, title text, start_datetime timestamptz, venue_name text,
               image_url text, reactions jsonb)
language sql stable security definer set search_path = public as $$
  select m.id, m.sender_id, p.display_name, p.avatar_url, m.kind, m.body, m.created_at, m.deleted_at is not null,
         e.id, e.slug, e.title, e.start_datetime, v.name, coalesce(e.image_urls[1], v.photo_url),
         coalesce((select jsonb_agg(jsonb_build_object('user_id', r.user_id, 'emoji', r.emoji)) from chat_reactions r where r.message_id = m.id), '[]'::jsonb)
  from chat_messages m
  left join profiles p on p.id = m.sender_id
  left join events e on e.id = m.event_id
  left join venues v on v.id = e.venue_id
  where m.conversation_id = p_conversation and is_chat_member(p_conversation)
    and (p_before is null or m.created_at < p_before)
  order by m.created_at desc
  limit least(greatest(coalesce(p_limit, 60), 1), 200);
$$;

create or replace function public.chat_members_of(p_conversation uuid)
returns table (user_id uuid, display_name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url from chat_members m join profiles p on p.id = m.user_id
  where m.conversation_id = p_conversation and is_chat_member(p_conversation) order by p.display_name;
$$;

grant execute on function public.chat_open_direct(uuid), public.chat_create_group(text, uuid[], text),
  public.chat_add_members(uuid, uuid[]), public.chat_leave(uuid), public.chat_set_muted(uuid, boolean),
  public.chat_send(uuid, text, text, uuid), public.chat_mark_read(uuid), public.chat_react(uuid, text),
  public.chat_delete_message(uuid), public.chat_inbox(), public.chat_unread_total(),
  public.chat_thread(uuid, timestamptz, integer), public.chat_members_of(uuid), public.is_chat_member(uuid)
  to authenticated;
