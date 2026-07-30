-- Vollständige Provenienz- und Review-Metadaten für den automatisierten
-- Entitätsbildimport. Additiv, damit bestehende images-Zeilen weiter gelten.
alter table images
  add column if not exists source_page_url text,
  add column if not exists source_name text,
  add column if not exists original_image_url text,
  add column if not exists license_name text,
  add column if not exists license_url text,
  add column if not exists confidence_score numeric(4,3),
  add column if not exists match_reason text,
  add column if not exists warnings text[] not null default '{}',
  add column if not exists is_primary boolean not null default false,
  add column if not exists fetched_at timestamptz not null default now(),
  add column if not exists content_hash text,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references profiles(id);

alter table images drop constraint if exists images_license_status_check;
alter table images add constraint images_license_status_check check (
  license_status in (
    'confirmed_free', 'confirmed_licensed', 'official_press_image',
    'permission_required', 'unknown', 'rejected'
  )
);
alter table images add constraint images_confidence_score_check
  check (confidence_score is null or confidence_score between 0 and 1);

create index if not exists images_review_queue_idx
  on images (needs_review, imported_at desc) where needs_review;
create index if not exists images_content_hash_idx
  on images (content_hash) where content_hash is not null;
create unique index if not exists images_one_primary_per_origin_idx
  on images (origin_type, origin_id) where is_primary;

comment on column images.source_page_url is 'Seite, auf der das Bild gefunden wurde; source_url bleibt die direkte Bild-URL.';
comment on column images.confidence_score is '0..1: technische/semantische Sicherheit der Zuordnung, keine Lizenzbewertung.';
comment on column images.match_reason is 'Nachvollziehbare Begründung der Zuordnung für die redaktionelle Review-Queue.';
comment on column images.content_hash is 'SHA-256 des heruntergeladenen Originals zur exakten Duplikaterkennung.';
