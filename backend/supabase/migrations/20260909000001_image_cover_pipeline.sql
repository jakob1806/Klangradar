-- Erweiterung des Bild-Lizenz-Tracking-Modells (20260819000003_images_and_tags.sql)
-- für die automatische Bilderkennungs-/Download-Pipeline im Event-Importer
-- (ingest-source): Downloads, WebP-/Thumbnail-Erzeugung und pHash-basierte
-- Duplikaterkennung brauchen mehr Metadaten als die bisherige reine
-- URL-Referenz-Zeile. Rein additiv, keine bestehende Spalte/Policy verändert.

alter table images
  add column width int,
  add column height int,
  add column mime_type text,
  add column credits text,
  add column license text,
  add column phash text,
  add column thumbnail_path text;

comment on column images.credits is
  'Automatisch extrahierter Bildnachweis (z.B. "Foto: ...", "Photographer: ..."), getrennt von copyright_notice (reiner ©-Vermerk).';
comment on column images.phash is
  'Perceptual Hash (DCT-basiert, 64 Bit als Hex-String) für Duplikaterkennung über verschiedene source_url/Quellen hinweg — siehe _shared/imagePipeline.ts. Exakter Stringvergleich, keine Hamming-Distanz-Suche.';
comment on column images.thumbnail_path is
  'Storage-Pfad der kleinen Vorschauvariante (WebP), parallel zu storage_path (volle Größe). Null wenn nur die volle Größe gespeichert werden konnte.';

-- Exakte pHash-Übereinstimmung (dieselbe Bilddatei, evtl. andere source_url
-- oder anderes Origin) günstig nachschlagen können, ohne eine Distanz-Suche
-- über alle Zeilen laufen zu lassen.
create index images_phash_idx on images (phash) where phash is not null;

-- Storage-Bucket "ingested-images" (Downloads aus dem Importer: Event-,
-- Ensemble-, Künstler- und Venue-Coverbilder, siehe Fallback-Kaskade in
-- ingest-source/write.ts) wird — wie schon "entity-photos" in
-- 20260825000001_entity_photo_uploads.sql — außerhalb von Migrationen
-- angelegt (Dashboard/CLI), da storage.buckets hier projektübergreifend
-- nicht per SQL verwaltet wird:
--
--   supabase storage buckets create ingested-images --public
--
-- Public=true, damit Storage öffentliche URLs ausliefert. Keine eigenen
-- storage.objects-Policies nötig (anders als bei entity-photos): Schreiben
-- passiert ausschließlich serverseitig über den Service-Role-Key der Edge
-- Functions, der RLS ohnehin umgeht — entity-photos braucht Policies, weil
-- dort das Admin-Frontend mit Nutzer-Session (anon key) direkt hochlädt.
