-- Abschnitt 6: resolve-person-duplicates merged/löscht bisher bei hoher
-- KI-Konfidenz vollautomatisch, ohne Review — das widerspricht der sonst
-- im Projekt durchgängig befolgten Regel ("keine irreversiblen Merges ohne
-- ausdrückliche Autorisierung", siehe z.B. work_duplicate_candidates:
-- "bewusst NICHT automatisch zusammengeführt", 20260909000003). Auf
-- Nutzerentscheidung umgestellt auf Review-Pflicht — das KI-Urteil landet
-- ab sofort immer hier, nie mehr als direkter Löschvorgang.
alter table person_duplicate_candidates
  add column ai_recommends_merge boolean,
  add column ai_reasoning text;
