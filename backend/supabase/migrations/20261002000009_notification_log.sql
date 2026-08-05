-- Phase A.1 (docs/09-feature-expansion-plan.md): serverseitiges Auslösen von
-- Push-Benachrichtigungen. notification_log verhindert, dass ein Nutzer für
-- dieselbe Veranstaltung/denselben Anlass mehrfach benachrichtigt wird, wenn
-- der Cron-Job mehrmals über denselben Zeitraum läuft (analog zu
-- price_checked_at/references_checked_at als Wiederholungs-Sperre, hier pro
-- (Nutzer, Event, Anlass) statt pro Datensatz).
create table notification_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  notification_type text not null,
  sent_at timestamptz not null default now(),
  unique (user_id, event_id, notification_type)
);

alter table notification_log enable row level security;

-- Nur der Service-Role-Key (Edge Functions) schreibt/liest hier — kein
-- Client-Zugriff nötig, analog zu system_logs.
create policy "notification_log service role only"
  on notification_log for all
  using (false)
  with check (false);
