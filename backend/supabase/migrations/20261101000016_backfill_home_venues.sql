-- Trägt home_venue_id für einen Teil der in 20261101000011-000014 importierten
-- Ensembles nach (dort war home_venue_slug für ALLE 128 Ensembles leer, siehe
-- docs/12-city-expansion-import.md). Bewusst nur die Fälle, in denen die
-- Zuordnung eindeutig und öffentlich bekannt ist (namensgleiche/institutionell
-- untrennbare Orchester/Chöre ihres Opernhauses/Saals) — keine geratenen
-- Verknüpfungen für die übrigen ~110 Ensembles, das bleibt offene
-- redaktionelle Nacharbeit.
update ensembles set home_venue_id = (select id from venues where slug = v.venue_slug)
from (values
  ('berliner-philharmoniker', 'philharmonie-berlin-grosser-saal'),
  ('staatskapelle-berlin', 'staatsoper-unter-den-linden'),
  ('staatsopernchor-berlin', 'staatsoper-unter-den-linden'),
  ('orchester-der-deutschen-oper-berlin', 'deutsche-oper-berlin'),
  ('chor-der-deutschen-oper-berlin', 'deutsche-oper-berlin'),
  ('orchester-der-komischen-oper-berlin', 'komische-oper-berlin'),
  ('chor-der-komischen-oper-berlin', 'komische-oper-berlin'),
  ('konzerthausorchester-berlin', 'konzerthaus-berlin-grosser-saal'),
  ('ndr-elbphilharmonie-orchester', 'elbphilharmonie-grosser-saal'),
  ('philharmonisches-staatsorchester-hamburg', 'hamburgische-staatsoper'),
  ('chor-der-hamburgischen-staatsoper', 'hamburgische-staatsoper'),
  ('frankfurter-opern-und-museumsorchester', 'oper-frankfurt'),
  ('opernchor-frankfurt', 'oper-frankfurt'),
  ('wiener-philharmoniker', 'musikverein-wien-grosser-saal'),
  ('wiener-symphoniker', 'wiener-konzerthaus-grosser-saal'),
  ('orchester-der-wiener-staatsoper', 'wiener-staatsoper'),
  ('orchester-der-volksoper-wien', 'volksoper-wien'),
  ('wiener-sangerknaben', 'muth-konzertsaal-der-wiener-sangerknaben')
) as v(ensemble_slug, venue_slug)
where ensembles.slug = v.ensemble_slug;
