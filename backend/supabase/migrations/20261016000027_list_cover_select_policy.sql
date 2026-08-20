-- Bugfix: Titelbild-Upload für eigene Listen schlug mit "new row violates
-- row-level security policy" (403) fehl — reproduziert und isoliert über
-- direkte Storage-API-Aufrufe: derselbe anonyme Test-User konnte erfolgreich
-- nach profile-avatars hochladen, aber nicht nach list-covers. Unterschied:
-- 20261010000003_user_profile_details.sql hat profile-avatars bewusst eine
-- SELECT-Policy nachgerüstet ("Storage benötigt bei einem Upload mit
-- x-upsert zusätzlich SELECT, um ein bereits vorhandenes Objekt sicher
-- ersetzen zu können") — list-covers wurde in 20261016000020 ohne diese
-- SELECT-Policy angelegt und blieb dadurch für x-upsert-Uploads permanent
-- blockiert, auch beim allerersten Hochladen ohne vorhandenes Objekt.
create policy "Nutzer liest eigenes Listen-Titelbild-Objekt"
on storage.objects for select to authenticated
using (
  bucket_id = 'list-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);
