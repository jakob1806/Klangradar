-- Folgemigration zu 20261217000004: In der Live-DB existiert zusätzlich ein
-- separates Ensemble "Solist(en) des Tölzer Knabenchors" (z.B. als Rolle
-- "Erscheinung 3" in G. Verdi: Macbeth, Nationaltheater München). Die
-- Schreibvariante wird als Alias des kanonischen Ensembles eingetragen.
insert into entity_aliases (entity_type, entity_id, alias)
select 'ensemble', e.id, alias
from ensembles e
cross join (
  values
    ('Solist(en) des Tölzer Knabenchors'),
    ('Solist(en) des Tölzer Knabenchores')
) as v(alias)
where e.slug = 'toelzer-knabenchor'
on conflict (entity_type, entity_id, alias_normalized) do nothing;

-- Rückwirkender Backfill: Der Trigger canonicalize_alias_references() (siehe
-- 20261013000016) biegt beim Einfügen eines Alias die event_participants-,
-- Favoriten- und Source-Verweise einer bereits existierenden Ensemble-Zeile
-- mit genau diesem normalisierten Namen auf das kanonische Ensemble um. Für
-- Aliasse, die schon vorher existierten (on conflict do nothing), feuert er
-- nicht — daher hier einmal explizit für alle Aliasse des Chors anstoßen.
-- Die alte Ensemble-Zeile bleibt bewusst bestehen (Duplikate-Prüfung).
update entity_aliases a
set alias = a.alias
from ensembles e
where a.entity_type = 'ensemble'
  and a.entity_id = e.id
  and e.slug = 'toelzer-knabenchor';
