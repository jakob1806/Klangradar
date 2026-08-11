-- Repair the public entity photo bucket and its editor write policies.
-- The native editorial client uploads with an authenticated JWT and an
-- upsert-capable request, so it needs insert, select, update and delete.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'entity-photos',
  'entity-photos',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Redaktion liest Entity-Fotos" on storage.objects;
drop policy if exists "Redaktion lädt Entity-Fotos hoch" on storage.objects;
drop policy if exists "Redaktion aktualisiert Entity-Fotos" on storage.objects;
drop policy if exists "Redaktion löscht Entity-Fotos" on storage.objects;

create policy "Redaktion liest Entity-Fotos"
on storage.objects for select to authenticated
using (
  bucket_id = 'entity-photos'
  and public.is_admin_or_editor()
);

create policy "Redaktion lädt Entity-Fotos hoch"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'entity-photos'
  and public.is_admin_or_editor()
);

create policy "Redaktion aktualisiert Entity-Fotos"
on storage.objects for update to authenticated
using (
  bucket_id = 'entity-photos'
  and public.is_admin_or_editor()
)
with check (
  bucket_id = 'entity-photos'
  and public.is_admin_or_editor()
);

create policy "Redaktion löscht Entity-Fotos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'entity-photos'
  and public.is_admin_or_editor()
);
