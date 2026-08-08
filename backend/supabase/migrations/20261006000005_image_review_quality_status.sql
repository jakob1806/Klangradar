-- Erweiterte Review-/Qualitäts-Zustandsmaschine + fehlende Metadatenfelder
-- für die zentrale Bilddatenbank (images-Tabelle) — Nutzerwunsch: eine
-- klar unterscheidbare review_status (pending/approved/rejected/
-- needs_manual_review) statt nur des bisherigen binären needs_review, und
-- ein quality_status (valid/low_resolution/unreachable/invalid_format/
-- duplicate/copyright_unclear), der unabhängig von der Lizenzfrage ist —
-- ein Bild kann technisch einwandfrei UND lizenzrechtlich ungeklärt sein,
-- oder technisch mangelhaft UND lizenzrechtlich bereits bestätigt.
--
-- needs_review UND license_status bleiben unverändert bestehen (Nutzer-
-- wunsch: "Vorhandene Felder... sollen weiterverwendet werden") — rein
-- additiv, kein bestehendes Feld wird umbenannt/entfernt/umgedeutet.
alter table images
  add column if not exists review_status text not null default 'pending'
    check (review_status in ('pending', 'approved', 'rejected', 'needs_manual_review')),
  add column if not exists quality_status text not null default 'valid'
    check (quality_status in ('valid', 'low_resolution', 'unreachable', 'invalid_format', 'duplicate', 'copyright_unclear')),
  add column if not exists file_size_bytes bigint,
  add column if not exists alt_text text,
  add column if not exists caption text,
  add column if not exists last_checked_at timestamptz;

comment on column images.review_status is
  'Redaktioneller Freigabestatus, unabhängig von license_status (das bewertet nur die Lizenz, nicht ob überhaupt ein Mensch das Bild geprüft hat). needs_manual_review = automatisch als unsicher genug eingestuft, dass eine reine Ja/Nein-Freigabe nicht reicht.';
comment on column images.quality_status is
  'Technische Bildqualität, unabhängig von Lizenz/Review. low_resolution = unter der Pipeline-Mindestauflösung (640x480 laut isAcceptableImageDimensions in _shared/imagePipeline.ts), bleibt aber weiterhin anzeigbar, bis ein Ersatz bestätigt ist.';
comment on column images.last_checked_at is
  'Letzte automatisierte Erreichbarkeits-/Qualitätsprüfung — getrennt von reviewed_at (menschliche redaktionelle Prüfung, siehe 20260910000004).';

create index if not exists images_review_status_idx on images (review_status);
create index if not exists images_quality_status_idx on images (quality_status) where quality_status <> 'valid';

-- Backfill review_status aus dem bisherigen needs_review/license_status:
-- eine bereits bestätigte Lizenz ohne offene Prüfung zählt als
-- "approved", eine abgelehnte Lizenz als "rejected", alles andere bleibt
-- beim Default "pending" (keine stille Auto-Freigabe unbekannter Zeilen).
update images set review_status = 'approved'
  where license_status in ('confirmed_free', 'confirmed_licensed', 'official_press_image')
    and needs_review = false;
update images set review_status = 'rejected'
  where license_status = 'rejected';

-- Backfill quality_status: JEDE bestehende Zeile unter der Mindest-
-- auflösung markieren (deckt automatisch auch die drei bekannten Fälle
-- ab — Nationaltheater München 225x225, sowie jedes Venue-Foto unter
-- 640 Breite oder 480 Höhe), ohne den Datensatz selbst zu verändern
-- (Nutzerwunsch: "ohne bestehende Datensätze oder Zuordnungen zu
-- beschädigen... sollen weiterhin angezeigt werden können, bis ein
-- Ersatz bestätigt wurde").
update images set quality_status = 'low_resolution'
  where width is not null and height is not null
    and (width < 640 or height < 480);

-- Nachtrag zur "zentralen Bilddatenbank": Fotos, die über das ältere,
-- direkte Admin-Upload-Formular (image-upload-field.tsx, Bucket
-- "entity-photos") gesetzt wurden, hatten bisher GAR KEINE Zeile in
-- images — nur eine rohe URL in persons/venues/ensembles.photo_url,
-- außerhalb jeder zentralen Nachverfolgung. Rückwirkend als images-Zeilen
-- erfassen (Maße/Dateigröße live per HEAD/Download ermittelt, siehe
-- Session-Notizen), damit sie im Admin-Bereich wie jedes andere Bild
-- Qualitäts-/Review-Status zeigen. storage_path bleibt bewusst NULL (die
-- Datei liegt im "entity-photos"-Bucket, nicht im sonst überall
-- angenommenen "ingested-images"-Bucket) — source_url ist bereits eine
-- voll funktionsfähige öffentliche Storage-URL und dient als Fallback-
-- Anzeige-URL (siehe app/lib/core/gallery/entity_gallery_providers.dart).
-- review_status='approved': die Fotos sind bereits live im Einsatz, ein
-- Mensch hat sie beim Hochladen implizit freigegeben.
insert into images (
  origin_type, origin_id, source_url, source_name, width, height,
  file_size_bytes, mime_type, quality_status, review_status,
  license_status, is_primary, needs_review, imported_at, fetched_at
)
select v.origin_type, v.origin_id, v.source_url, 'Manueller Admin-Upload',
  v.width, v.height, v.file_size_bytes, 'image/jpeg', v.quality_status,
  'approved', 'unknown', true, false, now(), now()
from (values
  ('venue', 'df97bb11-57b4-4cbe-b513-e3db4c2074ba'::uuid,
    'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/entity-photos/venues/84ee4751-9616-4c5f-9093-819573d546eb.jpeg',
    225, 225, 11574, 'low_resolution'),
  ('venue', '956c3276-d7b4-4def-bed6-d20c2ceed549'::uuid,
    'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/entity-photos/venues/598559d3-7140-418a-a27b-e87ddb692d06.jpg',
    700, 420, 53587, 'low_resolution'),
  ('venue', '00000000-0000-0000-0000-000000000001'::uuid,
    'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/entity-photos/venues/9660dd7c-7616-45e0-bc4e-02f8041a6984.jpg',
    400, 267, 21496, 'low_resolution'),
  ('person', 'f883d591-71e3-4933-ad6c-6e1bf7c7df05'::uuid,
    'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/entity-photos/persons/e45de201-03c0-48ec-a51d-8156431be78e.jpg',
    683, 1024, 46045, 'valid'),
  ('person', 'aca59d6f-d218-4474-b437-fb89c0ff31f5'::uuid,
    'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/entity-photos/persons/d4eec70f-40eb-4b56-8113-6b30566ebd47.jpg',
    1086, 723, 191053, 'valid'),
  ('ensemble', 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'::uuid,
    'https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/entity-photos/ensembles/4c5884dc-0798-4c6e-876a-decc6de4fc53.jpg',
    1600, 995, 244442, 'valid')
) as v(origin_type, origin_id, source_url, width, height, file_size_bytes, quality_status)
where not exists (
  select 1 from images existing
  where existing.origin_type = v.origin_type and existing.origin_id = v.origin_id
);
