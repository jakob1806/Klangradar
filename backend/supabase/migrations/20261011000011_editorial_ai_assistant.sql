-- Gemeinsames, persistentes Gedächtnis und nachvollziehbare Chats für den
-- redaktionellen Gemini-Assistenten. Inhalte sind ausschließlich für
-- Admins/Redakteure sichtbar; die Edge Function schreibt mit Service Role.
create table editorial_ai_settings (
  id boolean primary key default true check (id),
  instructions text not null default 'Antworte auf Deutsch, sachlich und ohne Werbesprache. Biografien umfassen 3–5 Sätze. Verwende nur belegte Fakten. Bevorzuge offizielle Websites, Kulturinstitutionen, Werkverlage und Normdaten. Kennzeichne Widersprüche und rate nicht. Datumswerte im Format YYYY-MM-DD, Nationalitäten auf Deutsch.',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into editorial_ai_settings (id) values (true) on conflict (id) do nothing;

create table editorial_ai_threads (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('event', 'person', 'ensemble', 'work')),
  entity_id uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (entity_type, entity_id, created_by)
);

create table editorial_ai_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references editorial_ai_threads(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  proposals jsonb not null default '[]'::jsonb,
  sources jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index editorial_ai_messages_thread_created_idx
  on editorial_ai_messages(thread_id, created_at);

alter table editorial_ai_settings enable row level security;
alter table editorial_ai_threads enable row level security;
alter table editorial_ai_messages enable row level security;

create policy editorial_ai_settings_editor_all on editorial_ai_settings
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy editorial_ai_threads_editor_all on editorial_ai_threads
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy editorial_ai_messages_editor_all on editorial_ai_messages
  for all using (
    is_admin_or_editor() and exists (
      select 1 from editorial_ai_threads t where t.id = thread_id
    )
  ) with check (
    is_admin_or_editor() and exists (
      select 1 from editorial_ai_threads t where t.id = thread_id
    )
  );

grant select, insert, update on editorial_ai_settings to authenticated;
grant select, insert, update, delete on editorial_ai_threads to authenticated;
grant select, insert, update, delete on editorial_ai_messages to authenticated;
