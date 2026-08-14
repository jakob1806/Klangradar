create table person_audit_flags (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references persons(id) on delete cascade,
  full_name text not null,
  issues jsonb not null,
  status text not null default 'open' check (status in ('open', 'resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (person_id)
);

create index person_audit_flags_status_idx on person_audit_flags (status, created_at desc);

alter table person_audit_flags enable row level security;

create policy "Redaktion liest Namensprüfung" on person_audit_flags
  for select using (is_admin_or_editor());

create policy "Redaktion schreibt Namensprüfung" on person_audit_flags
  for insert with check (is_admin_or_editor());

create policy "Redaktion aktualisiert Namensprüfung" on person_audit_flags
  for update using (is_admin_or_editor()) with check (is_admin_or_editor());

create policy "Redaktion löscht Namensprüfung" on person_audit_flags
  for delete using (is_admin_or_editor());
