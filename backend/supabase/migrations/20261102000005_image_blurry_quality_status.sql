-- Nutzerwunsch: "Schärfe-Heuristik (Laplacian-Varianz o.ä.) zusätzlich zu
-- Mindestauflösung/Seitenverhältnis, um unscharfe/verpixelte Treffer vor
-- der Freigabe auszusortieren." ensureCoverImageInner() (imagePipeline.ts)
-- lehnt zu unscharfe Bilder jetzt mit reason='too_blurry' ab — dieser Wert
-- braucht einen passenden Platz im bestehenden quality_status-Enum aus
-- 20261006000005_image_review_quality_status.sql.
alter table images drop constraint images_quality_status_check;
alter table images add constraint images_quality_status_check
  check (quality_status in ('valid', 'low_resolution', 'unreachable', 'invalid_format', 'duplicate', 'copyright_unclear', 'blurry'));
