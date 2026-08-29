-- Bestätigte Verwalter dürfen Bilder ausschließlich in ihrem eigenen
-- Upload-Präfix ablegen. Sichtbar wird eine URL erst, wenn der zugehörige
-- Profiländerungsvorschlag redaktionell genehmigt wurde.
create policy "Claimed users upload profile media" on storage.objects
  for insert with check (
    bucket_id = 'entity-photos'
    and name like 'claimed/%'
    and split_part(name, '/', 3) = auth.uid()::text
  );
