-- Ticket Intelligence (Nutzeranfrage): "Defekte oder nicht mehr gültige
-- Ticketlinks automatisch erkennen". event_ticket_links bekommt zwei neue
-- Spalten für das Ergebnis der periodischen Prüfung (siehe Edge Function
-- check-ticket-links). last_checked_at ist bewusst hier statt auf events —
-- mit mehreren Anbietern pro Event (20261016000017) kann jeder Link einen
-- eigenen Gesundheitszustand haben.
alter table event_ticket_links add column if not exists last_checked_at timestamptz;
alter table event_ticket_links add column if not exists is_broken boolean not null default false;
create index if not exists event_ticket_links_check_due_idx
  on event_ticket_links (last_checked_at nulls first);
