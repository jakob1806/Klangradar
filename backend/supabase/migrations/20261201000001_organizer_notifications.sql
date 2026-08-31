-- Veranstalterportal: Postfach/Benachrichtigungen (Nutzerwunsch: "deutliche
-- Erweiterung im Bereich der Navigation und Funktionalität"). notification_log
-- ist ein reiner Push-Dedup-Log für Endnutzer (RLS blockiert jeden Client-
-- Zugriff, keine read_at/Nachrichtentext-Spalten) — für einen echten
-- Veranstalter-Posteingang ungeeignet, deshalb eine eigene, kleine Tabelle
-- nach demselben RLS-Grundmuster wie entity_claims/event_promotions.
create table organizer_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  organizer_id uuid references organizers(id) on delete cascade,
  type text not null check (type in (
    'claim_approved', 'claim_rejected',
    'promotion_approved', 'promotion_rejected', 'promotion_payment_failed',
    'team_invite_received', 'team_role_changed'
  )),
  title text not null,
  body text,
  link_href text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index organizer_notifications_user_idx on organizer_notifications(user_id, created_at desc);
create index organizer_notifications_unread_idx on organizer_notifications(user_id) where read_at is null;

alter table organizer_notifications enable row level security;

-- Redaktion erzeugt Benachrichtigungen im Zuge von Claim-/Promotion-Reviews
-- (siehe entity-claims/actions.ts, event-promotions/actions.ts) — gleiches
-- Muster wie "Redaktion verwaltet Claims" auf entity_claims.
create policy "Redaktion verwaltet Notifications" on organizer_notifications
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Empfänger sieht ausschließlich eigene Benachrichtigungen und darf davon
-- nur read_at setzen (kein Insert/Delete durch den Client, kein Zugriff auf
-- fremde Zeilen über eine manipulierte user_id — with check erzwingt das).
create policy "Nutzer sieht eigene Notifications" on organizer_notifications
  for select using (auth.uid() = user_id);

create policy "Nutzer markiert eigene Notifications als gelesen" on organizer_notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
