-- Agenturen sind Veranstalter-Kontexte mit einem zusätzlich gepflegten Roster.
-- Sie werden absichtlich nicht in Endnutzer-Apps veröffentlicht.
create table organizer_agency_roster (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references organizers(id) on delete cascade,
  entity_type text not null check (entity_type in ('person', 'ensemble')),
  entity_id uuid not null,
  added_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  unique (organizer_id, entity_type, entity_id)
);

create index organizer_agency_roster_organizer_idx on organizer_agency_roster(organizer_id);
alter table organizer_agency_roster enable row level security;
create policy "Team sieht eigenes Agentur-Roster" on organizer_agency_roster for select
  using (has_approved_organizer_claim(organizer_id));
create policy "Redaktion pflegt eigenes Agentur-Roster" on organizer_agency_roster for insert
  with check (added_by = auth.uid() and has_organizer_capability(organizer_id, 'events'));
create policy "Redaktion entfernt eigenes Agentur-Roster" on organizer_agency_roster for delete
  using (has_organizer_capability(organizer_id, 'events'));
