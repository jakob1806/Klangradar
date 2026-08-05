-- Phase B.2 (docs/09-feature-expansion-plan.md), Nutzerwunsch Punkt 13:
-- schlanke Meldefunktion statt aufwendigem Communitysystem. Bewusst eine
-- EIGENE Tabelle statt error_reports zweckzuentfremden — error_reports ist
-- reines App-Crash-/Fehler-Logging (source/message/context für technische
-- Fehler), keine inhaltlichen Nutzerhinweise zu Events/Venues/Personen.
-- Meldungen ändern nie direkt Daten (siehe Nutzerwunsch: "Meldungen gehen in
-- eine Review-Queue und verändern Daten nicht unmittelbar"), nur Redaktion
-- entscheidet über status.
create table content_reports (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('event', 'venue', 'person', 'ensemble')),
  entity_id uuid not null,
  reporter_id uuid references profiles(id) on delete set null,
  reason text not null check (reason in (
    'wrong_image', 'wrong_time', 'cancelled', 'wrong_artist',
    'broken_ticket_link', 'missing_program', 'other'
  )),
  message text,
  status text not null default 'pending' check (status in ('pending', 'resolved', 'dismissed')),
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_content_reports_status on content_reports(status, created_at desc);

alter table content_reports enable row level security;

-- Jeder eingeloggte Nutzer (auch anonyme Auth-Sessions, siehe
-- 06-mvp-plan.md "Auth: anonym + Sign in with Apple/Google") kann eigene
-- Meldungen anlegen, aber nur unter der eigenen reporter_id — kein Spoofen
-- fremder Meldungen.
create policy "Nutzer melden eigene Reports" on content_reports
  for insert with check (auth.uid() = reporter_id);

create policy "Redaktion verwaltet Reports" on content_reports
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());
