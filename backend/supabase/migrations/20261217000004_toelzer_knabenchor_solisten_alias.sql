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
    ('Solist(en) des Tölzer Knabenchors'),
    ('Solist(en) des Tölzer Knabenchores')
) as v(alias)
where e.slug = 'toelzer-knabenchor'
on conflict (entity_type, entity_id, alias_normalized) do nothing;

-- Rückwirkender Backfill: Der Trigger canonicalize_alias_references() (siehe
-- 20261013000016) biegt beim Einfügen eines Alias die event_participants-,
-- Favoriten- und Source-Verweise einer bereits existierenden Ensemble-Zeile
-- mit genau diesem normalisierten Namen auf das kanonische Ensemble um
-- (z.B. das separat angelegte "Solist(en) des Tölzer Knabenchors"). Für
-- Aliasse, die schon vorher existierten (on conflict do nothing), feuert er
-- nicht — daher hier einmal explizit für alle Aliasse des Chors anstoßen.
-- Die alte Ensemble-Zeile bleibt bewusst bestehen (Duplikate-Prüfung).
update entity_aliases a
set alias = a.alias
from ensembles e
where a.entity_type = 'ensemble'
  and a.entity_id = e.id
  and e.slug = 'toelzer-knabenchor';
