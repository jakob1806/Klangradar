-- Löschen für Venues/Ensembles/Personen/Veranstaltungen aus dem
-- Redaktionsportal DER NATIVEN APP (ios-native) — Nutzervorgabe "der admin
-- darf veranstaltungen, ensembles, personen, venues usw. löschen". Das
-- Web-Admin-Portal hat diese Cascade-Detach-Logik bereits in TypeScript
-- (admin/src/app/(dashboard)/{venues,ensembles,persons}/actions.ts); hier
-- als SQL-Funktionen dupliziert, damit die native App (Swift) sie über
-- einen einzigen rpc()-Aufruf nutzen kann, statt die mehrschrittige
-- Detach-Reihenfolge in Swift nachzubauen (Fehlerrisiko bei fehlenden
-- ON DELETE CASCADE-Constraints). Web-Admin bleibt unverändert auf der
-- eigenen TS-Implementierung — beide Wege führen zum selben Ergebnis, siehe
-- die jeweiligen detach*References()-Kommentare dort für die Begründung
-- der einzelnen Schritte.
--
-- events braucht keine eigene Funktion: event_works/event_participants/
-- cancellation_candidates haben bereits ON DELETE CASCADE auf events(id)
-- (20260715000010_event_relations.sql) — ein einfaches
-- supabase.rpc("delete_event", ...) o.ä. wäre nur ein Wrapper um
-- `delete from events where id = ...`, das kann die native App auch direkt
-- über den generischen DELETE-Client-Call machen (siehe
-- SupabaseRESTClient.delete). programs-Leerlauf-Aufräumen (siehe
-- 20261013000009) übernimmt delete_event trotzdem mit, damit die native App
-- nicht auch noch diese Sonderregel kennen muss.

create or replace function delete_venue(p_venue_id uuid)
returns void
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
end;
$$;

create or replace function delete_ensemble(p_ensemble_id uuid)
returns void
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
end;
$$;

create or replace function delete_person(p_person_id uuid)
returns void
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
end;
$$;

create or replace function delete_event(p_event_id uuid)
returns void
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
end;
$$;
