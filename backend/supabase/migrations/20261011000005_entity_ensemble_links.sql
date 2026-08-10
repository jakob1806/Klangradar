-- Nutzeranfrage: Personen/Ensembles sollen sich untereinander mit einem
-- übergeordneten Ensemble verknüpfen lassen, z. B. "Solist(en) des Tölzer
-- Knabenchors" (persons) gehört zum Ensemble "Tölzer Knabenchor", oder
-- "Kammerorchester des Symphonieorchesters des Bayerischen Rundfunks"
-- (ensembles) gehört zum Ensemble "Symphonieorchester des Bayerischen
-- Rundfunks". Zwei getrennte, nullable self-/cross-referencing FKs statt
-- einer generischen Relationstabelle — genau die zwei angefragten Fälle,
-- kein allgemeines Beziehungsmodell nötig.

alter table ensembles add column parent_ensemble_id uuid references ensembles(id) on delete set null;
alter table ensembles add constraint ensembles_parent_not_self check (parent_ensemble_id is null or parent_ensemble_id <> id);
alter table persons add column member_of_ensemble_id uuid references ensembles(id) on delete set null;

create index idx_ensembles_parent_ensemble on ensembles(parent_ensemble_id);
create index idx_persons_member_of_ensemble on persons(member_of_ensemble_id);
