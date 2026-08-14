-- Nutzervorgabe: "roles" bei Personen soll nicht auf einen festen Katalog
-- (bisher das participant_role-Enum: komponist/dirigent/solist/chorleiter/
-- moderator) beschränkt sein, sondern auch Begriffe wie "Regisseur" oder
-- "Schauspieler" zulassen. Bisher schlug ein von der KI-Qualitätsprüfung
-- vorgeschlagener, nicht im Enum enthaltener Rollenwert beim Übernehmen mit
-- einem Postgres-Fehler ("invalid input value for enum participant_role")
-- fehl — das war die Ursache für "KI-Korrekturen übernehmen" bei mehreren
-- ausgewählten Personen-Treffern in der Qualitätsprüfung.
--
-- Nur persons.roles wird geöffnet, event_participants.role bleibt bewusst
-- beim Enum (dort gibt es bereits ein separates freies role_label-Feld für
-- den Einzeltermin-Fall, siehe 20261002-Migration "event participant role
-- labels"). Rückwärtskompatibel: text[] akzeptiert weiterhin alle
-- bisherigen Enum-Werte, keine bestehende Schreibstelle muss angepasst
-- werden.
alter table persons alter column roles type text[] using roles::text[];
alter table persons alter column roles set default '{}'::text[];
