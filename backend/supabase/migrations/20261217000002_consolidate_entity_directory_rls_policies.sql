-- Fortsetzung von 20261217000001 (Nutzeranfrage: "dann die nächsten
-- Tabellen angehen") — dieselbe Konsolidierung für die drei Verzeichnis-
-- Tabellen mit dem höchsten echten Abfrageaufkommen laut
-- `supabase inspect db table-stats` (Sequential Scans seit letztem
-- Stats-Reset): persons (85.193, 1.761 Zeilen), venues (78.221, 249
-- Zeilen), ensembles (63.608, 287 Zeilen) — mit deutlichem Abstand vor den
-- übrigen, im Advisor gemeldeten Tabellen (die meisten davon
-- Organizer-Portal-Tabellen mit ein- bis niedrig-zweistelligem
-- Abfrageaufkommen, z.B. event_series nur 13 Scans, organizers 356).
--
-- Gleiches Muster wie events: alle drei hatten pro Tabelle 2 gestapelte
-- SELECT-Policies ("Öffentlich lesbar" + die SELECT-Wirkung der FOR-ALL-
-- Redaktions-Policy) und 2 gestapelte UPDATE-Policies (dieselbe FOR-ALL-
-- Policy + "Claimed users update …"). INSERT/DELETE hatten schon immer nur
-- die eine FOR-ALL-Policy und sind vom Advisor nicht gemeldet.
--
-- Inhaltlich unverändert: dieselben Personen dürfen exakt dasselbe wie
-- zuvor. is_admin_or_editor()/has_approved_claim() sind beide `stable`,
-- das `(select …)`-Wrapping macht sie zu einem einmal pro Statement
-- ausgewerteten InitPlan statt einer erneuten Auswertung pro Zeile.

-- persons ---------------------------------------------------------------
drop policy "Redaktion verwaltet Personen" on persons;
drop policy "Öffentlich lesbar" on persons;
drop policy "Claimed users update persons" on persons;

create policy "Personen lesbar" on persons
  for select using (true);

create policy "Redaktion legt Personen an" on persons
  for insert with check ((select is_admin_or_editor()));

create policy "Redaktion und Claim-Owner bearbeiten Personen" on persons
  for update
  using ((select is_admin_or_editor()) or has_approved_claim('person', id))
  with check ((select is_admin_or_editor()) or has_approved_claim('person', id));

create policy "Redaktion löscht Personen" on persons
  for delete using ((select is_admin_or_editor()));

-- venues ------------------------------------------------------------------
drop policy "Redaktion verwaltet Venues" on venues;
drop policy "Öffentlich lesbar" on venues;
drop policy "Claimed users update venues" on venues;

create policy "Venues lesbar" on venues
  for select using (true);

create policy "Redaktion legt Venues an" on venues
  for insert with check ((select is_admin_or_editor()));

create policy "Redaktion und Claim-Owner bearbeiten Venues" on venues
  for update
  using ((select is_admin_or_editor()) or has_approved_claim('venue', id))
  with check ((select is_admin_or_editor()) or has_approved_claim('venue', id));

create policy "Redaktion löscht Venues" on venues
  for delete using ((select is_admin_or_editor()));

-- ensembles -----------------------------------------------------------------
-- Einziger Unterschied zu persons/venues: Auflösungs-Platzhalter
-- (is_resolution_placeholder) bleiben für alle außer Redaktion unsichtbar —
-- exakt wie in der bisherigen "Öffentlich lesbar"-Policy.
drop policy "Redaktion verwaltet Ensembles" on ensembles;
drop policy "Öffentlich lesbar" on ensembles;
drop policy "Claimed users update ensembles" on ensembles;

create policy "Ensembles lesbar" on ensembles
  for select using ((not is_resolution_placeholder) or (select is_admin_or_editor()));

create policy "Redaktion legt Ensembles an" on ensembles
  for insert with check ((select is_admin_or_editor()));

create policy "Redaktion und Claim-Owner bearbeiten Ensembles" on ensembles
  for update
  using ((select is_admin_or_editor()) or has_approved_claim('ensemble', id))
  with check ((select is_admin_or_editor()) or has_approved_claim('ensemble', id));

create policy "Redaktion löscht Ensembles" on ensembles
  for delete using ((select is_admin_or_editor()));

-- images ----------------------------------------------------------------
-- Anderes Muster als persons/venues/ensembles: hier stapelten sich ZWEI
-- FOR-ALL-Policies ("Redaktion verwaltet Bilder", "Claimed users manage
-- their gallery images") übereinander mit einer SELECT-spezifischen
-- Freigabe-Policy — macht die Konsolidierung für alle vier Befehle
-- relevant (24 gemeldete Advisor-Einträge = 6 Rollen × 4 Befehle), nicht
-- nur SELECT/UPDATE wie bei den drei Verzeichnis-Tabellen oben.
drop policy "Redaktion verwaltet Bilder" on images;
drop policy "Claimed users manage their gallery images" on images;
drop policy "Bilder sind öffentlich lesbar, wenn freigegeben" on images;

create policy "Bilder lesbar" on images
  for select using (
    license_status = any (array['confirmed_free', 'confirmed_licensed'])
    or (select is_admin_or_editor())
    or (origin_type = any (array['person', 'ensemble', 'venue']) and has_approved_claim(origin_type, origin_id))
  );

create policy "Redaktion und Claim-Owner verwalten Bilder (Schreiben)" on images
  for insert with check (
    (select is_admin_or_editor())
    or (origin_type = any (array['person', 'ensemble', 'venue']) and has_approved_claim(origin_type, origin_id))
  );

create policy "Redaktion und Claim-Owner bearbeiten Bilder" on images
  for update
  using (
    (select is_admin_or_editor())
    or (origin_type = any (array['person', 'ensemble', 'venue']) and has_approved_claim(origin_type, origin_id))
  )
  with check (
    (select is_admin_or_editor())
    or (origin_type = any (array['person', 'ensemble', 'venue']) and has_approved_claim(origin_type, origin_id))
  );

create policy "Redaktion und Claim-Owner löschen Bilder" on images
  for delete using (
    (select is_admin_or_editor())
    or (origin_type = any (array['person', 'ensemble', 'venue']) and has_approved_claim(origin_type, origin_id))
  );

-- event_genres --------------------------------------------------------------
-- Gleiches Zwei-FOR-ALL-plus-SELECT-Muster wie images, direkt bei jeder
-- Event-Abfrage mitgejoint (event_genres.seq_scans laut table-stats: 1.821).
drop policy "Redaktion verwaltet event_genres" on event_genres;
drop policy "Beanspruchte Künstler pflegen Event-Genres" on event_genres;
drop policy "Öffentlich lesbar" on event_genres;

create policy "event_genres lesbar" on event_genres
  for select using (true);

create policy "Redaktion und Claim-Owner verwalten event_genres (Schreiben)" on event_genres
  for insert with check (
    (select is_admin_or_editor()) or has_claimed_profile_event_edit_access(event_id)
  );

create policy "Redaktion und Claim-Owner bearbeiten event_genres" on event_genres
  for update
  using ((select is_admin_or_editor()) or has_claimed_profile_event_edit_access(event_id))
  with check ((select is_admin_or_editor()) or has_claimed_profile_event_edit_access(event_id));

create policy "Redaktion und Claim-Owner löschen event_genres" on event_genres
  for delete using (
    (select is_admin_or_editor()) or has_claimed_profile_event_edit_access(event_id)
  );
