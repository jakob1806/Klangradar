-- Nutzerfeedback: Beim Tölzer Knabenchor fehlen auf dessen Entity-Seite viele
-- Veranstaltungen, an denen er mitwirkt (z.B. Opernproduktionen der
-- Bayerischen Staatsoper). Ursache: die Besetzungsliste nennt den Chor dort
-- oft nicht als "Tölzer Knabenchor", sondern als "Solisten des Tölzer
-- Knabenchores" (nur ein Teil des Chors singt die jeweilige Partie). Die
-- Trigram-Ähnlichkeit zwischen diesem deutlich längeren Text und dem
-- kanonischen Namen "Tölzer Knabenchor" liegt unter dem 0.5-Schwellwert von
-- find_matching_ensemble() (siehe 20261013000020_distinguish_venues_
-- organizers_and_ensembles.sql) — der Teilnehmer wird deshalb nie verknüpft,
-- sondern bliebe (falls überhaupt) als eigener, falscher Ensemble-Kandidat
-- hängen. Ein expliziter Alias-Eintrag macht daraus einen exakten
-- normalisierten Treffer (siehe 20261013000016_canonical_entity_alias_
-- system.sql), unabhängig vom Trigram-Score.
insert into entity_aliases (entity_type, entity_id, alias)
select 'ensemble', e.id, alias
from ensembles e
cross join (
  values
    ('Solisten des Tölzer Knabenchores'),
    ('Solisten des Tölzer Knabenchors'),
    ('Solistinnen und Solisten des Tölzer Knabenchores'),
    ('Solist(en) des Tölzer Knabenchors')
) as v(alias)
where e.slug = 'toelzer-knabenchor'
on conflict (entity_type, entity_id, alias_normalized) do nothing;

-- Live-Fund (2026-09-30, Produktions-DB): genau dieser Schreibvarianten-Bug
-- hatte bereits einen doppelten, unverifizierten Ensemble-Datensatz
-- "Solist(en) des Tölzer Knabenchors" (be1b4064-8e88-46ff-a74c-4e21439983a9)
-- erzeugt, verknüpft mit genau einer Aufführung (Macbeth, 05.07.2027), bei
-- der die echte "Tölzer Knabenchor"-Zeile (cddeab2f-a6bb-47d2-a12f-
-- 3145d1697d02) bereits separat verknüpft war. Zusammenführen nach demselben
-- Muster wie 20260909000007_merge_munich_philharmonic_duplicate.sql.
update field_provenance
set entity_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
where entity_type = 'ensemble' and entity_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9'
  and field_name not in (
    select field_name from field_provenance
    where entity_type = 'ensemble' and entity_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
  );
delete from field_provenance
where entity_type = 'ensemble' and entity_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';

-- Zeilen ohne bestehenden Konflikt auf das echte Ensemble umhängen (der
-- unique index event_participants_event_ensemble_uniq verbietet sonst ein
-- zweites Mal denselben (event_id, ensemble_id)); wo das Event bereits die
-- echte Zeile hat, bleibt nur die überflüssige Dublette zum Löschen übrig.
update event_participants ep
set ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
where ep.ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9'
  and not exists (
    select 1 from event_participants other
    where other.event_id = ep.event_id and other.ensemble_id = 'cddeab2f-a6bb-47d2-a12f-3145d1697d02'
  );
delete from event_participants where ensemble_id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';

delete from ensembles where id = 'be1b4064-8e88-46ff-a74c-4e21439983a9';

-- Live-Recherche (2026-09-30): toelzerknabenchor.de listet u.a. 6 weitere
-- "DIE ZAUBERFLÖTE"-Vorstellungen (Nov/Dez 2026) an der Bayerischen
-- Staatsoper, deren Besetzung ("Drei Knaben" -> "Solist(en) des Tölzer
-- Knabenchors") live auf staatsoper.de bestätigt ist, in event_participants
-- aber komplett fehlt — obwohl staatsoper_detail_synced_at bereits gesetzt
-- ist (Sync lief am 13.08.2026, vermutlich bevor die Besetzung final
-- veröffentlicht war). hydrate-staatsoper-events synct aber nur EINMAL pro
-- Event (Filter `is("staatsoper_detail_synced_at", null)`), ein späteres
-- Cast-Update wird dadurch nie mehr eingesammelt — ein eigenständiges,
-- über den Tölzer-Knabenchor-Fall hinausgehendes Problem. Reset hier nur für
-- die konkret bestätigten Termine, damit der nächste reguläre Sync-Lauf sie
-- mit dem jetzt korrekt auflösenden Alias erneut abgreift.
update events
set staatsoper_detail_synced_at = null, staatsoper_detail_sync_error = null
where id in (
  'f1ea6a71-7073-4e7c-b3a4-63cd0386f24e', -- Die Zauberflöte 2026-11-20
  '73c47269-cc46-413e-90bb-c45870025b79', -- Die Zauberflöte 2026-11-22
  'de5c27bd-1c42-4dc6-8d7a-e4b2284e6351', -- Die Zauberflöte 2026-11-27
  'e3712429-bb5d-4ebf-a1d9-f13554365f21', -- Die Zauberflöte 2026-11-29
  '9197c425-2d7b-410f-afb4-381b8c6a6d20', -- Die Zauberflöte 2026-12-03
  '910e3666-8439-479b-8502-8b1beb7b88f4'  -- Die Zauberflöte 2026-12-06
);
