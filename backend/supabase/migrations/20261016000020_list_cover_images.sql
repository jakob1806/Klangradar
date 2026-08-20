-- Nutzeranfrage: "Listen sollen auch auf der Homepage angezeigt werden
-- können, gleiches Verhalten wie redaktionelle Sammlungen, nur dass das eine
-- vom Nutzer selbst in der App gemacht werden kann und das andere vom
-- Admin-Portal ausgeht" — eigene favorite_lists bekommen ein optionales
-- Titelbild (cover_image_url), analog zu editorial_collections.cover_
-- image_url, damit sie auf der Home-Startseite als eigene Kachelreihe
-- erscheinen können.
alter table favorite_lists add column if not exists cover_image_url text;

-- Titelbilder werden öffentlich dargestellt (wie profile-avatars), Schreib-/
-- Löschzugriff bleibt strikt auf den eigenen Listen-Ordner (<auth.uid()>/
-- <list_id>.jpg) begrenzt.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'list-covers',
  'list-covers',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Nutzer lädt eigenes Listen-Titelbild hoch"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'list-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Nutzer aktualisiert eigenes Listen-Titelbild"
on storage.objects for update to authenticated
using (
  bucket_id = 'list-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'list-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Nutzer löscht eigenes Listen-Titelbild"
on storage.objects for delete to authenticated
using (
  bucket_id = 'list-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);
