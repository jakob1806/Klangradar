-- Nutzerfeedback (2026-09-30, nach 20261217000004/-005): "Es gibt vier
-- Profile: Tölzer Knabenchor, Tölzer Knabenchor, Solist des Tölzer
-- Knabenchors, Solisten des Tölzer Knabenchores." Live-Recherche in der
-- Produktions-DB bestätigt zwei zusätzliche Dubletten, die bisher nicht
-- erfasst waren, weil sie NICHT als Ensemble, sondern fälschlich als PERSON
-- angelegt wurden (persons-Tabelle statt ensembles):
--   - "Tölzer Knabenchor" (Person, 12 Events: 6x Die Zauberflöte, 4x
--     Tannhäuser, 2x Macbeth, alles Bayerische Staatsoper)
--   - "Solist des Tölzer Knabenchors" (Person, 3 Events: BRSO, Sir Simon
--     Rattle | Pelléas et Mélisande) — bestätigt denselben Bug auch außerhalb
--     der Staatsoper-Quelle.
-- assessEnsembleName() in entityNameValidation.ts würde beide Namen heute
-- als "ensemble" klassifizieren (enthalten "Chor") und ihre Anlage als
-- Person in enrich-event-references/index.ts::flagEntityCandidate() aktiv
-- verhindern (Zeile ~649: `if (entityType === "person" && nameAssessment.safe) return null`)
-- — es handelt sich also um Alt-Daten von vor dieser Schutzschicht, kein
-- aktueller Code-Bug. Reiner Backfill: person_id-Verweise auf ensemble_id
-- des kanonischen Ensembles ummappen (keine Kollisionen mit dem unique index
-- event_participants_event_ensemble_uniq geprüft), verwaiste Personenzeilen
-- danach löschen. Ergänzt außerdem die noch fehlende Singular-Schreibweise
-- als Alias, damit künftige Sync-Läufe sie sofort korrekt auflösen.

insert into entity_aliases (entity_type, entity_id, alias)
select 'ensemble', e.id, 'Solist des Tölzer Knabenchors'
from ensembles e
where e.slug = 'toelzer-knabenchor'
on conflict (entity_type, entity_id, alias_normalized) do nothing;

-- Person "Tölzer Knabenchor" (73c99391-d90d-4ea7-824a-76befd31f20f) ->
-- Ensemble "Tölzer Knabenchor" (cddeab2f-a6bb-47d2-a12f-3145d1697d02).
update event_participants ep
set person_id = null, ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
where ep.person_id = '73c99391-d90d-4ea7-824a-76befd31f20f'
  and not exists (
    select 1 from event_participants other
    where other.event_id = ep.event_id and other.ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
  );
delete from event_participants where person_id = '73c99391-d90d-4ea7-824a-76befd31f20f';
-- Deploy-Fix (2026-10-04): der erste Lauf schlug mit einer FK-Verletzung fehl
-- (entity_candidates.created_person_id verwies noch auf die Person; per
-- anon-Key wegen RLS unsichtbar, daher bei der Vorprüfung übersehen). Die
-- nicht kaskadierenden Verweise auf persons (entity_candidates, sources,
-- works) werden jetzt vor jedem Löschen gelöst. Die Migration war nie
-- angewendet (Transaktion zurückgerollt), daher direkte Korrektur.
update entity_candidates set created_person_id = null, created_ensemble_id = coalesce(created_ensemble_id, 'cddeab2f-a6bb-47d2-a12f-3145d1697d02')
  where created_person_id = '73c99391-d90d-4ea7-824a-76befd31f20f';
update sources set person_id = null where person_id = '73c99391-d90d-4ea7-824a-76befd31f20f';
update works set composer_id = null where composer_id = '73c99391-d90d-4ea7-824a-76befd31f20f';
delete from persons where id = '73c99391-d90d-4ea7-824a-76befd31f20f';

-- Person "Solist des Tölzer Knabenchors" (87d57ec1-77fe-4f97-b6c1-917c60e02e1e)
-- -> selbes kanonisches Ensemble. Eine biography_de-Provenienzzeile zuerst
-- migrieren (gleiches Muster wie beim Ensemble-Merge in 20260909000007).
update field_provenance
set entity_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02', entity_type = 'ensemble'
where entity_type = 'person' and entity_id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e'
  and field_name not in (
    select field_name from field_provenance
    where entity_type = 'ensemble' and entity_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
  );
delete from field_provenance
where entity_type = 'person' and entity_id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e';

update event_participants ep
set person_id = null, ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
where ep.person_id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e'
  and not exists (
    select 1 from event_participants other
    where other.event_id = ep.event_id and other.ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
  );
delete from event_participants where person_id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e';
update entity_candidates set created_person_id = null, created_ensemble_id = coalesce(created_ensemble_id, 'cddeab2f-a6bb-47d2-a12f-3145d1697d02')
  where created_person_id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e';
update sources set person_id = null where person_id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e';
update works set composer_id = null where composer_id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e';
delete from persons where id = '87d57ec1-77fe-4f97-b6c1-917c60e02e1e';

-- Die von 20261217000005 bewusst stehen gelassene Ensemble-Dublette
-- "Solist(en) des Tölzer Knabenchors" (be1b4064-8e88-46ff-a74c-4e21439983a9,
-- Alias existiert bereits, event_participants/field_provenance dadurch schon
-- umgebogen) jetzt endgültig aufräumen — sie taucht sonst weiterhin als
-- eigenes, leeres Profil in Suche/Verzeichnis auf (Teil der vom Nutzer
-- gemeldeten "vier Profile").
update field_provenance
set entity_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
where entity_type = 'ensemble' and entity_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9'
  and field_name not in (
    select field_name from field_provenance
    where entity_type = 'ensemble' and entity_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
  );
delete from field_provenance
where entity_type = 'ensemble' and entity_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';
update event_participants ep
set ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
where ep.ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9'
  and not exists (
    select 1 from event_participants other
    where other.event_id = ep.event_id and other.ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
  );
delete from event_participants where ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';
update entity_candidates set created_ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02' where created_ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';
update sources set ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02' where ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';
update ensembles set parent_ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02' where parent_ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';
delete from user_favorite_ensembles f where f.ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9'
  and exists (select 1 from user_favorite_ensembles g where g.user_id = f.user_id and g.ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02');
update user_favorite_ensembles set ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02' where ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';
delete from ensembles where id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';
