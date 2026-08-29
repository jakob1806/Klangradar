-- Veranstalter-Portal Phase 8: Agenturen und Artist Roster.
create table agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 160),
  website_url text,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);
create table agency_members (
  agency_id uuid not null references agencies(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'editor')),
  primary key (agency_id, user_id)
);
create table agency_roster (
  agency_id uuid not null references agencies(id) on delete cascade,
  entity_type text not null check (entity_type in ('person', 'ensemble')),
  entity_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (agency_id, entity_type, entity_id)
);
create index agency_roster_entity_idx on agency_roster(entity_type, entity_id);

create function has_agency_role(p_agency_id uuid, p_roles text[] default array['owner','editor']) returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from agency_members where agency_id = p_agency_id and user_id = auth.uid() and role = any(p_roles));
$$;

alter table agencies enable row level security;
alter table agency_members enable row level security;
alter table agency_roster enable row level security;
create policy "Redaktion verwaltet Agenturen" on agencies for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Redaktion verwaltet Agenturmitglieder" on agency_members for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Redaktion verwaltet Agenturroster" on agency_roster for all using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Agentur sieht eigene Daten" on agencies for select using (has_agency_role(id));
create policy "Nutzer gründet eigene Agentur" on agencies for insert with check (created_by = auth.uid());
create policy "Agentur sieht eigene Mitglieder" on agency_members for select using (has_agency_role(agency_id));
create policy "Gründer wird Agentur-Owner" on agency_members for insert with check (
  user_id = auth.uid() and role = 'owner'
  and exists (select 1 from agencies where id = agency_id and created_by = auth.uid())
);
create policy "Agentur sieht eigenes Roster" on agency_roster for select using (has_agency_role(agency_id));
create policy "Agentur bearbeitet eigenes Roster" on agency_roster for all using (has_agency_role(agency_id)) with check (has_agency_role(agency_id));
