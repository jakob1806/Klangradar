-- Performance-Optimierung: Supabase Performance-Advisor meldet für
-- `events` (mit Abstand meistgefragte Tabelle, 169.902 Sequential Scans
-- seit dem letzten Stats-Reset laut `supabase inspect db table-stats`)
-- mehrere gestapelte permissive Policies pro Befehl — Postgres wertet bei
-- SELECT/INSERT/UPDATE jeweils ALLE folgenden einzeln aus und verknüpft sie
-- per OR, statt eine einzige kombinierte Bedingung zu prüfen:
--   SELECT: "Veröffentlichte Events sind lesbar", "Redaktion verwaltet
--     Events", "Veranstalter sieht eigene Events",
--     "Beanspruchte Künstler sehen verknüpfte Events" (4 Policies)
--   INSERT: "Redaktion verwaltet Events", "Team legt eigene Events an" (2)
--   UPDATE: "Redaktion verwaltet Events", "Team bearbeitet eigene Events",
--     "Beanspruchte Künstler bearbeiten verknüpfte Events" (3)
-- Das war bisher unauffällig, weil die komplette DB in den RAM-Cache passt
-- (100% Cache-Hit-Rate), skaliert aber linear mit der Zeilenzahl mit — die
-- Multi-City-Erweiterung hat `events` von ~280 auf ~1.991 Zeilen wachsen
-- lassen (Nutzeranfrage: "fang mit events an", nach DB-Metriken-Check).
--
-- Jede Sicht/jeder Befehl bekommt jetzt genau EINE Policy mit denselben
-- Bedingungen per OR verknüpft — inhaltlich identisch zum Vorher-Zustand
-- (dieselben Personen dürfen exakt dasselbe wie zuvor), nur nicht mehr als
-- separate Postgres-Policies. DELETE hatte schon immer nur eine einzige
-- Policy ("Redaktion verwaltet Events" deckte als FOR ALL auch DELETE ab)
-- und ist vom Advisor nicht als "multiple_permissive_policies" gemeldet —
-- bleibt inhaltlich unverändert bei "nur Redaktion".
--
-- is_admin_or_editor()/has_approved_organizer_claim()/
-- has_organizer_capability()/has_claimed_profile_event_edit_access() sind
-- alle bereits `stable`, das `(select …)`-Wrapping macht sie zusätzlich zu
-- einem einmal pro Statement ausgewerteten InitPlan statt einer erneuten
-- Auswertung pro Zeile (derselbe Effekt wie beim separat gemeldeten
-- "auth_rls_initplan"-Advisor-Befund, hier vorsorglich mit angewendet,
-- obwohl `events` dafür nicht explizit gelistet war).
drop policy "Veröffentlichte Events sind lesbar" on events;
drop policy "Redaktion verwaltet Events" on events;
drop policy "Veranstalter sieht eigene Events" on events;
drop policy "Beanspruchte Künstler sehen verknüpfte Events" on events;
drop policy "Team legt eigene Events an" on events;
drop policy "Team bearbeitet eigene Events" on events;
drop policy "Beanspruchte Künstler bearbeiten verknüpfte Events" on events;

create policy "Events lesbar" on events
  for select using (
    status != 'draft'
    or (select is_admin_or_editor())
    or (organizer_id is not null and has_approved_organizer_claim(organizer_id))
    or has_claimed_profile_event_edit_access(id)
  );

create policy "Redaktion und Team legen Events an" on events
  for insert
  with check (
    (select is_admin_or_editor())
    or (organizer_id is not null and has_organizer_capability(organizer_id, 'events') and status = 'draft')
  );

create policy "Redaktion und Team bearbeiten Events" on events
  for update
  using (
    (select is_admin_or_editor())
    or (organizer_id is not null and has_organizer_capability(organizer_id, 'events'))
    or has_claimed_profile_event_edit_access(id)
  )
  with check (
    (select is_admin_or_editor())
    or (organizer_id is not null and has_organizer_capability(organizer_id, 'events'))
    or has_claimed_profile_event_edit_access(id)
  );

create policy "Redaktion löscht Events" on events
  for delete using ((select is_admin_or_editor()));
