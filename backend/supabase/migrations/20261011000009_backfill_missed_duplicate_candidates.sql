-- Nutzerfeedback: "ich habe das gefühl, dass nach wie vor einige duplikate
-- entstehen. auch durch quellen wie concerti oder IN münchen, die
-- gesammelte konzertdaten zur verfügung bereitstellen." Konkret bestätigt:
-- die venuelosen Aggregator-Quellen "Concerti München" und "IN-Muenchen
-- (nur Klassik)" formulieren Titel oft komplett anders als die
-- Original-Quelle desselben Venues — die bisherige RPC-Schwelle (0.35,
-- siehe find_matching_event in 20260802000001) ließ solche Fälle OHNE
-- jeden duplicate_candidates-Eintrag durchrutschen, obwohl Venue und
-- Uhrzeit exakt übereinstimmten. matching.ts ruft die RPC ab sofort mit
-- Schwelle 0 auf (jedes Event im selben Venue/+-2h-Fenster wird jetzt
-- markiert) — das verhindert NEUE stille Duplikate, ändert aber nichts an
-- bereits VOR diesem Fix angelegten. Dieser einmalige Backfill holt genau
-- diese Lücke nach: alle bestehenden Venue+Zeitfenster-Kollisionen, die
-- noch in keiner duplicate_candidates-Zeile (in beide Richtungen) stehen,
-- werden nachträglich zur redaktionellen Prüfung markiert (Admin →
-- Duplikate-Review) — kein automatisches Zusammenführen, nur Sichtbarkeit.
insert into duplicate_candidates (event_a_id, event_b_id, similarity_score, status)
select
  e1.id,
  e2.id,
  similarity(e1.title, e2.title),
  'pending'
from events e1
join events e2
  on e1.venue_id = e2.venue_id
 and e1.id < e2.id
 and e2.start_datetime between e1.start_datetime - interval '2 hours'
                            and e1.start_datetime + interval '2 hours'
where e1.venue_id is not null
  and not exists (
    select 1 from duplicate_candidates dc
    where (dc.event_a_id = e1.id and dc.event_b_id = e2.id)
       or (dc.event_a_id = e2.id and dc.event_b_id = e1.id)
  );
