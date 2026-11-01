-- Erstellt von Claude Code (Nutzerwunsch 01.11.2026): Abo-Varianten nach
-- Wochentag. Viele Abos gibt es doppelt (z. B. BRSO Abo A am Donnerstag ODER
-- am Freitag mit demselben Programm). Die App speichert die gewählte Reihe
-- als ISO-Wochentag (1 = Montag … 7 = Sonntag); NULL = alle Termine.
alter table public.user_concert_subscriptions
  add column if not exists weekday smallint check (weekday is null or weekday between 1 and 7);
grant update on public.user_concert_subscriptions to authenticated;
drop policy if exists "Eigene Abos" on public.user_concert_subscriptions;
create policy "Eigene Abos" on public.user_concert_subscriptions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
