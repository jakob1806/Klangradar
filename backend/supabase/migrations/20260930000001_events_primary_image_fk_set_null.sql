-- events.primary_image_id hatte keine ON DELETE-Regel, daher blockierte
-- die FK jedes Löschen eines Bildes, das (auch versehentlich, z.B. durch
-- die Enrichment-Pipeline) als primäres Event-Bild gesetzt wurde.
-- ON DELETE SET NULL: Löschen bleibt möglich, das Event verliert nur sein
-- primäres Bild und fällt auf die bestehende image_urls[]-Anzeige zurück.

alter table events drop constraint events_primary_image_id_fkey;
alter table events add constraint events_primary_image_id_fkey
  foreign key (primary_image_id) references images(id) on delete set null;
