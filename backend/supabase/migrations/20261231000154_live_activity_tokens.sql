-- Erstellt von Claude Code (06.11.2026): Push-Tokens laufender Live-
-- Aktivitäten (Konzertabend), damit notify-changes Absagen, Zeit- und
-- Besetzungsänderungen direkt in die Aktivität schicken kann.
create table if not exists live_activity_tokens (
  token text primary key,               -- "apns:prod:<hex>" bzw. "apns:dev:<hex>"
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists live_activity_tokens_event_idx on live_activity_tokens(event_id);

alter table live_activity_tokens enable row level security;

drop policy if exists "live_activity_tokens_own_insert" on live_activity_tokens;
create policy "live_activity_tokens_own_insert" on live_activity_tokens
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "live_activity_tokens_own_update" on live_activity_tokens;
create policy "live_activity_tokens_own_update" on live_activity_tokens
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "live_activity_tokens_own_select" on live_activity_tokens;
create policy "live_activity_tokens_own_select" on live_activity_tokens
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "live_activity_tokens_own_delete" on live_activity_tokens;
create policy "live_activity_tokens_own_delete" on live_activity_tokens
  for delete to authenticated using (user_id = auth.uid());
