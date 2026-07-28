-- Bisher landete ein von der Initialen-Heuristik gefundenes, aber von der
-- KI nicht sicher genug bestätigtes Personen-Duplikat (resolve-person-
-- duplicates) einfach im Nichts — kein automatischer Merge, aber auch
-- keine Möglichkeit für die Redaktion, es zu sehen und selbst zu
-- entscheiden. Live beobachtet: "F. Mendelssohn" vs. "Felix Mendelssohn
-- Bartholdy" (Ambiguität mit Fanny Mendelssohn, ebenfalls eine reale
-- Komponistin) blieb dadurch dauerhaft als eigener, unvollständiger
-- Eintrag stehen. Mirrort work_duplicate_candidates (20260909000003).
create table person_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  person_a_id uuid references persons(id) on delete cascade,
  person_b_id uuid references persons(id) on delete cascade,
  status text default 'pending',
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz default now()
);

create unique index person_duplicate_candidates_pending_pair_idx
  on person_duplicate_candidates (least(person_a_id, person_b_id), greatest(person_a_id, person_b_id))
  where status = 'pending';

create index person_duplicate_candidates_status_idx on person_duplicate_candidates(status) where status = 'pending';

alter table person_duplicate_candidates enable row level security;

create policy "Redaktion verwaltet Personen-Duplikate" on person_duplicate_candidates
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());
