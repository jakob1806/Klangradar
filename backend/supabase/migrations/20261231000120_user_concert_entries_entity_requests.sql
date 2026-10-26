-- Erstellt von Claude Code (26.10.2026): Eigene Konzerteinträge im
-- Journal-Stil (Konzerte, die nicht in Klangradar stehen) und Nutzeranfragen
-- für fehlende Orte/Werke/Personen/Ensembles an die Redaktion.

create table if not exists public.user_concert_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text check (title is null or char_length(title) <= 200),
  starts_at timestamptz not null,
  duration_minutes int check (duration_minutes is null or duration_minutes between 1 and 600),
  venue_id uuid references public.venues(id) on delete set null,
  venue_name text check (venue_name is null or char_length(venue_name) <= 200),
  -- [{ "work_id": uuid, "title": text, "composer": text }]
  program jsonb not null default '[]'::jsonb,
  -- [{ "kind": "person"|"ensemble", "id": uuid, "name": text, "role": text }]
  participants jsonb not null default '[]'::jsonb,
  note text check (note is null or char_length(note) <= 4000),
  photo_paths text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists user_concert_entries_user_idx on public.user_concert_entries(user_id, starts_at desc);
alter table public.user_concert_entries enable row level security;
create policy "Eigene Konzerteinträge" on public.user_concert_entries for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.user_concert_entries to authenticated;

create table if not exists public.entity_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  entity_type text not null check (entity_type in ('person', 'ensemble', 'venue', 'work')),
  name text not null check (char_length(name) between 2 and 200),
  context text check (context is null or char_length(context) <= 200),
  -- created = sofort angelegt (Anreicherung läuft), existing = gab es schon,
  -- needs_review = automatisch nicht möglich (z. B. Ort nicht gefunden)
  status text not null default 'pending' check (status in ('pending', 'created', 'existing', 'needs_review', 'rejected', 'done')),
  created_entity_id uuid,
  note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists entity_requests_open_idx on public.entity_requests(created_at desc) where status in ('pending', 'created', 'needs_review');
alter table public.entity_requests enable row level security;
create policy "Eigene Anfragen lesen" on public.entity_requests for select using (user_id = auth.uid());
create policy "Redaktion verwaltet Anfragen" on public.entity_requests for all using (is_admin_or_editor()) with check (is_admin_or_editor());
grant select on public.entity_requests to authenticated;
