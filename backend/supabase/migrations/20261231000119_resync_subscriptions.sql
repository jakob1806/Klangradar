-- Erstellt von Claude Code (26.10.2026): Die erste Abo-Zuordnung schrieb in
-- falsch benannte Tabellen (Fix in _shared/subscriptions.ts). Alle kommenden
-- Termine einmal neu abgleichen.
update events set subscriptions_synced_at = null where start_datetime >= now();
