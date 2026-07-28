-- 0.35 war für klassische Werktitel viel zu niedrig — "Konzert für X und
-- Orchester", "Symphonie Nr. N", "Streichquartett" sind so verbreitete
-- Vokabel-Muster, dass strukturell unterschiedliche Werke schon allein
-- dadurch über der Schwelle lagen (live beobachtet: "Symphonie Nr.7"
-- (Beethoven) vs. "Symphonie Nr. 3 a-Moll" (unbekannt) bei 0.542 — klar
-- unterschiedliche Werke). Kombiniert mit dem composer_id-Konflikt-Fix in
-- enrich-event-references/index.ts (dort werden Fälle mit zwei
-- widersprüchlichen Komponisten-IDs jetzt gar nicht erst als Kandidat
-- angelegt) auf 0.55 angehoben — deutlich näher an der 0.6-Auto-Merge-
-- Schwelle, lässt nur noch einen schmalen "wirklich unsicher"-Korridor für
-- die Review-Queue übrig.
create or replace function find_similar_works(
  p_title text,
  p_similarity_threshold numeric default 0.55,
  p_result_limit int default 5
)
returns table (
  id uuid,
  title text,
  composer_id uuid,
  catalog_number text,
  key_signature text,
  similarity numeric
)
language sql
stable
as $$
  select
    works.id,
    works.title,
    works.composer_id,
    works.catalog_number,
    works.key_signature,
    similarity(works.title, p_title) as similarity
  from works
  where similarity(works.title, p_title) >= p_similarity_threshold
  order by similarity(works.title, p_title) desc
  limit p_result_limit;
$$;

-- Bestehende, unter der neuen Schwelle liegende Kandidaten sind mit der
-- alten 0.35er-Schwelle entstanden und wären mit der neuen nie angelegt
-- worden — reines Rauschen, bereinigt statt der Redaktion zur Prüfung
-- vorgelegt.
delete from work_duplicate_candidates
where status = 'pending' and similarity_score < 0.55;
