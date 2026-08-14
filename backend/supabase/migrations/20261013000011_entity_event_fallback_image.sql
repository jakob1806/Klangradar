-- Nutzervorgabe: Standardbild für Personen/Ensembles, das für alle deren
-- Veranstaltungen ohne eigenes Bild verwendet wird — bewusst getrennt vom
-- bestehenden photo_url-Profilfoto (kann z.B. ein Konzertfoto statt eines
-- Porträts sein). Reuses die schon vorhandene Mehrfach-Bilder-Galerie
-- (images-Tabelle, origin_type='person'/'ensemble', siehe gallery-editor.tsx)
-- statt eines neuen Upload-Wegs: ein Bild aus der Galerie wird als
-- Veranstaltungs-Standardbild markiert. Der Partial-Unique-Index erzwingt
-- "höchstens eines pro Entität" auf DB-Ebene.
alter table images add column use_as_event_fallback boolean not null default false;

create unique index images_one_event_fallback_per_origin
  on images (origin_type, origin_id)
  where use_as_event_fallback = true;
