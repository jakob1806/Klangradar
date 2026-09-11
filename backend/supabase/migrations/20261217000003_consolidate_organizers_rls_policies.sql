-- Fortsetzung von 20261217000001/000002 (Nutzeranfrage: "nächste Tabellen
-- angehen") — organizers ist von den verbliebenen Advisor-Treffern die
-- einzige mit nennenswertem echtem Abfrageaufkommen (356 seq_scans laut
-- `supabase inspect db table-stats`, 16 Zeilen). Die übrigen offenen Treffer
-- (entity_claims 3 Zeilen, event_series 0 Zeilen/13 Scans,
-- entity_edit_suggestions 1 Zeile/4 Scans, event_promotions 1 Zeile/60
-- Scans, organizer_notifications 0 Zeilen/5 Scans, sowie ~27 weitere
-- Organizer-Portal-Tabellen mit einstelligem/niedrig-zweistelligem
-- Abfrageaufkommen) bleiben bewusst unangetastet — bei so geringem Traffic
-- überwiegt das Migrationsrisiko den Performance-Nutzen.
--
-- Gleiches Muster wie zuvor: die FOR-ALL-Redaktionspolicy stapelte sich mit
-- der SELECT- und der INSERT-spezifischen Policy (macht beide Befehle vom
-- Advisor gemeldet), UPDATE/DELETE hatten schon immer nur die eine
-- FOR-ALL-Policy. Inhaltlich unverändert, nur konsolidiert plus
-- `(select is_admin_or_editor())`-Wrapping (InitPlan statt Auswertung pro
-- Zeile).
drop policy "Redaktion verwaltet Organizers" on organizers;
drop policy "Öffentlich lesbar" on organizers;
drop policy "Veranstalter legt eigene Institution an" on organizers;

create policy "Organizers lesbar" on organizers
  for select using (true);

create policy "Redaktion und Veranstalter legen Organizers an" on organizers
  for insert
  with check (
    (select is_admin_or_editor())
    or (created_by = auth.uid())
  );

create policy "Redaktion bearbeitet Organizers" on organizers
  for update
  using ((select is_admin_or_editor()))
  with check ((select is_admin_or_editor()));

create policy "Redaktion löscht Organizers" on organizers
  for delete using ((select is_admin_or_editor()));
