-- Beschleunigt die beiden nativen Suchpfade. Beide Abfragen filtern zuerst
-- nach Zuordnung und danach nach kommenden, geplanten Events.
create index if not exists event_genres_genre_event_idx
  on event_genres (genre_id, event_id);

create index if not exists events_scheduled_start_idx
  on events (start_datetime, id)
  where status = 'scheduled';

-- event_attributes_attribute_idx existiert bereits in der Taxonomie-
-- Migration. Diese Variante deckt zusätzlich den anschließenden Join auf
-- event_id ab, ohne einen Heap-Lookup pro Treffer zu benötigen.
create index if not exists event_attributes_attribute_event_idx
  on event_attributes (attribute_id, event_id, weight desc);

-- Eine Bildzeile kann bei gleicher source_url ersetzt, neu zugeschnitten
-- oder anders priorisiert werden. Der Zeitstempel liefert den Clients dafür
-- einen stabilen Cache-Buster.
alter table images add column if not exists updated_at timestamptz not null default now();

create or replace function touch_image_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists images_touch_updated_at on images;
create trigger images_touch_updated_at
before update on images
for each row execute function touch_image_updated_at();
