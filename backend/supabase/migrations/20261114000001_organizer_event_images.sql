-- Veranstalter dürfen Bilder ausschließlich in ihrem eigenen, klar
-- abgegrenzten Upload-Präfix ablegen. Die Zuordnung zu einem Event wird
-- zusätzlich in der Server Action gegen den genehmigten Organizer-Claim
-- geprüft; das Storage-Präfix allein ist keine Bearbeitungsberechtigung.
create policy "Veranstalter lädt eigene Eventbilder hoch" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'entity-photos'
    and name like ('organizer-event-images/' || auth.uid()::text || '/%')
  );

create policy "Veranstalter liest eigene Eventbilder" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'entity-photos'
    and name like ('organizer-event-images/' || auth.uid()::text || '/%')
  );
