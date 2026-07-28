-- find_similar_works durchsuchte bisher ALLE works der gesamten DB
-- (Nutzeranfrage: "bei den Duplikaten handelt es sich ja auch immer nur um
-- Duplikate innerhalb eines Programmes eines Konzerts" — bestätigt live:
-- Treffer wie "Simple Symphony" vs. "Symphony No. 5" oder "Streichquintett
-- Nr. 2" vs. "Streichquartett Nr. 2" aus komplett unterschiedlichen
-- Konzerten hatten nichts miteinander zu tun, die generische Titel-Vokabel-
-- Überschneidung klassischer Werke ("Symphonie Nr. N", "Konzert für X und
-- Orchester") reicht DB-weit für viele zufällige Treffer über der Schwelle).
-- Der eigentliche Zweck (siehe 20260909000003) war immer, Titel-Varianten
-- DESSELBEN Werks innerhalb DESSELBEN Konzertprogramms zu erkennen (z.B.
-- "Sinfonie Nr. 4 c-moll" vs. "Sinfonie Nr. 4 c-moll 'Tragische'" im selben
-- Event) — daher jetzt zwingend auf Werke beschränkt, die bereits über
-- event_works mit dem übergebenen Event verknüpft sind.
create or replace function find_similar_works(
  p_title text,
  p_event_id uuid,
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
  join event_works on event_works.work_id = works.id
  where event_works.event_id = p_event_id
    and similarity(works.title, p_title) >= p_similarity_threshold
  order by similarity(works.title, p_title) desc
  limit p_result_limit;
$$;

-- Bestehende Kandidaten, die aus dem alten DB-weiten Vergleich stammen und
-- keine gemeinsame Veranstaltung teilen, sind reines Rauschen nach der
-- neuen Definition — als "distinct" markiert statt gelöscht (auditierbar,
-- gleiche Konvention wie das bestehende "Als unterschiedlich markieren").
update work_duplicate_candidates
set status = 'dismissed', reviewed_at = now()
where status = 'pending'
  and not exists (
    select 1 from event_works ewa
    join event_works ewb on ewa.event_id = ewb.event_id
    where ewa.work_id = work_duplicate_candidates.work_a_id
      and ewb.work_id = work_duplicate_candidates.work_b_id
  );
