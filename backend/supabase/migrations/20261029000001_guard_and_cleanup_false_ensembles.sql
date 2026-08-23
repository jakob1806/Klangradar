-- Stoppt die häufigste Ursache falscher Ensemble-Stammdaten bereits an der
-- Datenbankgrenze. Importer besitzen Service-Role-Rechte und würden reine
-- RLS-Prüfungen umgehen; ein BEFORE-Trigger gilt dagegen für jeden Writer.
create or replace function is_obvious_non_ensemble_name(value text)
returns boolean
language sql
immutable
parallel safe
as $$
  select value is null
    or length(btrim(value)) < 3
    or btrim(value) ~ '^[[:lower:]äöüß]'
    or btrim(value) ~ '[.!?;:]$'
    or array_length(regexp_split_to_array(btrim(value), '\s+'), 1) > 10
    or lower(value) ~ '(ticketverkauf|abendkasse|vorverkauf|einlass|kartenverkauf|reservierung|buchung|erhältlich|weitere informationen|mehr erfahren|jetzt buchen|hier klicken|ausverkauft)';
$$;

create or replace function guard_ensemble_name()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.name := regexp_replace(btrim(new.name), '\s+', ' ', 'g');
  if is_obvious_non_ensemble_name(new.name) then
    raise exception 'Kein plausibler Ensemblename: %', new.name;
  end if;
  if not lower(new.name) ~ '(chor|choir|orchester|orchestra|ensemble|philharmoni|sinfoniker|symphoniker|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)'
     and exists (
       select 1 from persons p
       where lower(regexp_replace(btrim(p.full_name), '\s+', ' ', 'g')) = lower(new.name)
     ) then
    raise exception 'Der Name gehört bereits zu einer Person: %', new.name;
  end if;
  return new;
end;
$$;

drop trigger if exists ensembles_guard_name on ensembles;
create trigger ensembles_guard_name
before insert or update of name on ensembles
for each row execute function guard_ensemble_name();

-- Eindeutige bestehende Fehlklassifikationen atomar zur gleichnamigen Person
-- umhängen. Sobald am Event bereits die Person verknüpft ist, wird nur der
-- doppelte Ensemble-Link entfernt.
with false_ensembles as (
  select e.id as ensemble_id, p.id as person_id
  from ensembles e
  join persons p on lower(regexp_replace(btrim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(e.name), '\s+', ' ', 'g'))
  where not lower(e.name) ~ '(chor|choir|orchester|orchestra|ensemble|philharmoni|sinfoniker|symphoniker|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)'
)
delete from event_participants ep
using false_ensembles f
where ep.ensemble_id = f.ensemble_id
  and exists (
    select 1 from event_participants existing
    where existing.event_id = ep.event_id and existing.person_id = f.person_id
  );

with false_ensembles as (
  select e.id as ensemble_id, p.id as person_id
  from ensembles e
  join persons p on lower(regexp_replace(btrim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(e.name), '\s+', ' ', 'g'))
  where not lower(e.name) ~ '(chor|choir|orchester|orchestra|ensemble|philharmoni|sinfoniker|symphoniker|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)'
)
update event_participants ep
set person_id = f.person_id, ensemble_id = null
from false_ensembles f
where ep.ensemble_id = f.ensemble_id;

-- Offensichtliche Ticket-/Fließtexte haben kein sinnvolles Ziel. Verweise
-- werden gelöst, die kaputten Stammdatensätze anschließend entfernt.
delete from event_participants ep using ensembles e
where ep.ensemble_id = e.id and lower(e.name) ~ '(ticketverkauf|abendkasse|vorverkauf|einlass|kartenverkauf|reservierung|buchung|erhältlich|weitere informationen|mehr erfahren|jetzt buchen|hier klicken|ausverkauft)';
update sources s set ensemble_id = null from ensembles e
where s.ensemble_id = e.id and lower(e.name) ~ '(ticketverkauf|abendkasse|vorverkauf|einlass|kartenverkauf|reservierung|buchung|erhältlich|weitere informationen|mehr erfahren|jetzt buchen|hier klicken|ausverkauft)';
update entity_candidates c set created_ensemble_id = null from ensembles e
where c.created_ensemble_id = e.id and lower(e.name) ~ '(ticketverkauf|abendkasse|vorverkauf|einlass|kartenverkauf|reservierung|buchung|erhältlich|weitere informationen|mehr erfahren|jetzt buchen|hier klicken|ausverkauft)';
delete from ensembles where lower(name) ~ '(ticketverkauf|abendkasse|vorverkauf|einlass|kartenverkauf|reservierung|buchung|erhältlich|weitere informationen|mehr erfahren|jetzt buchen|hier klicken|ausverkauft)';

-- Gleichnamige Personen-Dubletten erst löschen, nachdem alle Verweise oben
-- auf die Person umgezogen sind.
update sources s set ensemble_id = null
from ensembles e join persons p
  on lower(regexp_replace(btrim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(e.name), '\s+', ' ', 'g'))
where s.ensemble_id = e.id
  and not lower(e.name) ~ '(chor|choir|orchester|orchestra|ensemble|philharmoni|sinfoniker|symphoniker|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)';
update entity_candidates c set created_ensemble_id = null
from ensembles e join persons p
  on lower(regexp_replace(btrim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(e.name), '\s+', ' ', 'g'))
where c.created_ensemble_id = e.id
  and not lower(e.name) ~ '(chor|choir|orchester|orchestra|ensemble|philharmoni|sinfoniker|symphoniker|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)';
delete from ensembles e
using persons p
where lower(regexp_replace(btrim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(e.name), '\s+', ' ', 'g'))
  and not lower(e.name) ~ '(chor|choir|orchester|orchestra|ensemble|philharmoni|sinfoniker|symphoniker|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)';
