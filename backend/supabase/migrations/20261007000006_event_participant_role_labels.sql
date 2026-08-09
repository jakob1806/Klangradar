-- Veranstaltungsspezifische Rollen dürfen frei formuliert sein (z. B.
-- "Lady Macbeth", "Basssolist" oder "1. Violine"), ohne die dauerhaft in
-- persons.roles gespeicherte allgemeine Kategorie der Person zu verändern.
alter table event_participants
  add column if not exists role_label text;

comment on column event_participants.role_label is
  'Freie, nur für diese Veranstaltung geltende Rollenbezeichnung; role bleibt die optionale grobe Such-/Filterkategorie.';

update event_participants
set role_label = case role
  when 'komponist' then 'Komponist:in'
  when 'dirigent' then 'Dirigent:in'
  when 'solist' then 'Solist:in'
  when 'chorleiter' then 'Chorleiter:in'
  when 'moderator' then 'Moderator:in'
end
where role is not null
  and nullif(btrim(role_label), '') is null;

alter table event_participants
  drop constraint if exists event_participants_role_label_length;

alter table event_participants
  add constraint event_participants_role_label_length
  check (role_label is null or char_length(role_label) <= 160);
