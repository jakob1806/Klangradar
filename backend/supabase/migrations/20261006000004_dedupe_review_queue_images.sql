-- Aufräumen der bereits entstandenen Duplikate aus dem Bug, den die
-- vorangegangene imagePipeline.ts-Änderung (Origin-scoped Content-Hash-
-- Dedupe) an der Wurzel behebt: dieselbe
-- Quelle wurde wiederholt eingelesen und hat bei jedem Lauf eine weitere
-- needs_review-Zeile mit identischem Bildinhalt für dasselbe Origin
-- angelegt ("Identischer Bildinhalt war bereits im Storage vorhanden" in
-- der /media-Review-Queue, live als mehrere fast identische, teils kaputt
-- angezeigte Karten für dasselbe Event beobachtet).
--
-- Behält je (origin_type, origin_id, content_hash) nur die älteste Zeile,
-- löscht den Rest — nur unter needs_review=true (schon entschiedene Bilder
-- bleiben unangetastet) und nur, wo content_hash überhaupt gesetzt ist.
delete from images target
using images keep
where target.needs_review = true
  and target.content_hash is not null
  and keep.origin_type = target.origin_type
  and keep.origin_id = target.origin_id
  and keep.content_hash = target.content_hash
  and (keep.imported_at, keep.id) < (target.imported_at, target.id);
