-- PostgREST liefert bei "returns void" einen leeren Response-Body (204),
-- den der native Swift-Client (SupabaseRESTClient.rpc<Response: Decodable>)
-- nicht als generisches Response dekodieren kann (leere Data ist kein
-- valides JSON). "returns boolean" liefert stattdessen den literalen
-- Skalarwert "true" im Body, was der generische rpc()-Aufruf problemlos als
-- Bool dekodiert — kein Sonderfall in der ohnehin schon geteilten
-- Networking-Schicht nötig. Rückgabetyp ändern braucht DROP+CREATE, ein
-- reines CREATE OR REPLACE erlaubt keinen abweichenden Rückgabetyp.

drop function delete_venue(uuid);
create function delete_venue(p_venue_id uuid)
returns boolean
language plpgsql
security invoker
as $$
begin
  if not is_admin_or_editor() then
    raise exception 'Keine Admin- oder Redaktionsberechtigung.';
  end if;

  update events set venue_id = null where venue_id = p_venue_id;
  update ensembles set home_venue_id = null where home_venue_id = p_venue_id;
  update sources set venue_id = null where venue_id = p_venue_id;
  update entity_candidates set suggested_venue_id = null where suggested_venue_id = p_venue_id;

  delete from venues where id = p_venue_id;
  return true;
end;
$$;

drop function delete_ensemble(uuid);
create function delete_ensemble(p_ensemble_id uuid)
returns boolean
language plpgsql
security invoker
as $$
begin
  if not is_admin_or_editor() then
    raise exception 'Keine Admin- oder Redaktionsberechtigung.';
  end if;

  delete from event_participants where ensemble_id = p_ensemble_id;
  update sources set ensemble_id = null where ensemble_id = p_ensemble_id;
  update entity_candidates set created_ensemble_id = null where created_ensemble_id = p_ensemble_id;

  delete from ensembles where id = p_ensemble_id;
  return true;
end;
$$;

drop function delete_person(uuid);
create function delete_person(p_person_id uuid)
returns boolean
language plpgsql
security invoker
as $$
begin
  if not is_admin_or_editor() then
    raise exception 'Keine Admin- oder Redaktionsberechtigung.';
  end if;

  delete from event_participants where person_id = p_person_id;
  update works set composer_id = null where composer_id = p_person_id;
  update sources set person_id = null where person_id = p_person_id;
  update entity_candidates set created_person_id = null where created_person_id = p_person_id;

  delete from persons where id = p_person_id;
  return true;
end;
$$;

drop function delete_event(uuid);
create function delete_event(p_event_id uuid)
returns boolean
language plpgsql
security invoker
as $$
declare
  v_program_id uuid;
begin
  if not is_admin_or_editor() then
    raise exception 'Keine Admin- oder Redaktionsberechtigung.';
  end if;

  select program_id into v_program_id from events where id = p_event_id;

  delete from events where id = p_event_id;

  if v_program_id is not null and not exists (
    select 1 from events where program_id = v_program_id
  ) then
    delete from programs where id = v_program_id;
  end if;
  return true;
end;
$$;
