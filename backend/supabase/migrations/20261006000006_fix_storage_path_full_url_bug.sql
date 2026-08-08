-- Datenreparatur: zwei Admin-Server-Actions (gallery-actions.ts
-- addGalleryImage, event-groups/[id]/actions.ts addGroupImage) haben bisher
-- storage_path fälschlich auf die volle öffentliche source_url gesetzt statt
-- auf null. Die App (entity_gallery_providers.dart, GalleryImage.fromRow)
-- interpretiert storage_path als relativen Pfad INNERHALB des
-- "ingested-images"-Buckets und baut daraus per getPublicUrl() eine kaputte,
-- doppelt verschachtelte URL — das gefundene/live bestätigte Bug-Symptom:
-- Galerie-Bilder aus diesem Upload-Weg waren auf der Detailseite kurz
-- sichtbar (der synchron verfügbare photo_url-Hintergrund lief zuerst),
-- verschwanden dann aber, sobald die App auf die eigentliche Galerie
-- umschaltete und deren Bild-URL mit 404 fehlschlug.
--
-- Reparatur: jede Zeile, deren storage_path wie eine volle URL aussieht
-- (enthält "://"), auf null setzen — source_url enthält in genau diesen
-- Fällen bereits dieselbe funktionierende URL (beide Felder wurden vom
-- Bug immer identisch gesetzt), GalleryImage.fromRow fällt dann korrekt
-- darauf zurück. Zeilen mit einem ECHTEN relativen storage_path (der
-- normale, korrekte Fall aus ensureCoverImage()) sind von diesem Muster
-- nicht betroffen und bleiben unverändert.
update images
  set storage_path = null
  where storage_path like '%://%';
