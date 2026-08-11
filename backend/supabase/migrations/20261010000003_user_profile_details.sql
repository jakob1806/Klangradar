-- Erweiterte, vom Nutzer selbst verwaltete Profildaten.
alter table profiles
  add column if not exists birth_date date;

-- Storage benötigt bei einem Upload mit x-upsert zusätzlich SELECT, um ein
-- bereits vorhandenes Avatar-Objekt sicher ersetzen zu können.
create policy "Nutzer liest eigenes Profilbild-Objekt"
on storage.objects for select to authenticated
using (
  bucket_id = 'profile-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);
