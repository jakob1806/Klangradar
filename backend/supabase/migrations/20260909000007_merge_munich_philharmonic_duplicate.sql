-- Nutzerfeedback: "Konzerte der Münchner Philharmoniker werden nicht
-- richtig erfasst" — zwei Ursachen gefunden:
--
-- 1. Doppeltes Ensemble: "Münchner Philharmoniker" (Seed-Daten,
--    00000000-0000-0000-0000-000000000301) UND "Munich Philharmonic"
--    (eigenständig über entity_candidates angelegt, vermutlich weil eine
--    englischsprachige Quelle den Namen anders geschrieben hat). Merge auf
--    die kanonische deutsche Form, Alias für die englische Variante, damit
--    künftige Matches sie wiedererkennen.
-- 2. sources.ensemble_id war für die mphil.de-Quelle nie gesetzt — die
--    Auto-Verknüpfung in ingest-source/write.ts (linkSourceEntity, siehe
--    20260818000001_sources_person_ensemble.sql) griff deshalb nie, jedes
--    gescrapte Konzert blieb ohne Mitwirkende-Eintrag für das Orchester
--    selbst.
--
-- Wird zusammen mit der Titel-Präfix-Logik in write.ts ausgeliefert (siehe
-- PR) — der mphil.de-Seite fehlt ein echter Konzerttitel, die
-- ".m-mphil-concertlist__headline" ist nur eine Komponisten-Liste (z.B.
-- "Ravel Bernstein Strawinsky"), auf der eigenen Markenseite im Kontext
-- klar, in der App ohne Orchesternamen missverständlich.

update field_provenance
set entity_id = '00000000-0000-0000-0000-000000000301'
where entity_type = 'ensemble' and entity_id = '5a328661-f77c-4bc2-b07f-f0de681c7516'
  and field_name not in (
    select field_name from field_provenance
    where entity_type = 'ensemble' and entity_id = '00000000-0000-0000-0000-000000000301'
  );
delete from field_provenance
where entity_type = 'ensemble' and entity_id = '5a328661-f77c-4bc2-b07f-f0de681c7516';

update images set origin_id = '00000000-0000-0000-0000-000000000301'
where origin_type = 'ensemble' and origin_id = '5a328661-f77c-4bc2-b07f-f0de681c7516';

insert into entity_aliases (entity_type, entity_id, alias)
values ('ensemble', '00000000-0000-0000-0000-000000000301', 'Munich Philharmonic')
on conflict do nothing;

update entity_candidates set created_ensemble_id = '00000000-0000-0000-0000-000000000301'
where created_ensemble_id = '5a328661-f77c-4bc2-b07f-f0de681c7516';

delete from ensembles where id = '5a328661-f77c-4bc2-b07f-f0de681c7516';

update sources set ensemble_id = '00000000-0000-0000-0000-000000000301'
where id = '710e11e5-1241-4056-b839-400abf4c51e5'; -- Münchner Philharmoniker Konzertkalender
