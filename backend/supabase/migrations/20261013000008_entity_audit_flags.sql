-- Generalisiert person_audit_flags (nur Personen) auf alle vier
-- Qualitätsprüfungs-Entitätstypen (Personen, Ensembles, Venues,
-- Veranstaltungen) — Nutzervorgabe "genereller neuer Tab für
-- Qualitätsprüfungen ... bei dem man das, was nun für Künstler geht, bei
-- Venues, Veranstaltungen, Ensembles und Personen machen kann".

create table entity_audit_flags (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('person', 'ensemble', 'venue', 'event')),
  entity_id uuid not null,
  display_name text not null,
  issues jsonb not null,
  status text not null default 'open' check (status in ('open', 'resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (entity_type, entity_id)
);

create index entity_audit_flags_status_idx on entity_audit_flags (entity_type, status, created_at desc);

alter table entity_audit_flags enable row level security;

create policy "Redaktion liest Qualitätsprüfungen" on entity_audit_flags
  for select using (is_admin_or_editor());

create policy "Redaktion schreibt Qualitätsprüfungen" on entity_audit_flags
  for insert with check (is_admin_or_editor());

create policy "Redaktion aktualisiert Qualitätsprüfungen" on entity_audit_flags
  for update using (is_admin_or_editor()) with check (is_admin_or_editor());

create policy "Redaktion löscht Qualitätsprüfungen" on entity_audit_flags
  for delete using (is_admin_or_editor());

insert into entity_audit_flags (entity_type, entity_id, display_name, issues, status, created_at, resolved_at)
select 'person', person_id, full_name, issues, status, created_at, resolved_at
from person_audit_flags
on conflict (entity_type, entity_id) do nothing;

drop table person_audit_flags;
