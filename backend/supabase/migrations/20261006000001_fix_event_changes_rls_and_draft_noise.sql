-- Bugfix: Veröffentlichen eines Entwurfs im Admin-Dashboard schlug fehl mit
-- "new row violates row-level security policy for table 'event_changes'".
-- Ursache: log_event_changes() (20261002000011/20261002000014) läuft ohne
-- SECURITY DEFINER, das Admin-Dashboard schreibt aber über eine normale
-- authentifizierte Session (RLS-Rechte über is_admin_or_editor(), siehe
-- admin/src/lib/supabase/server.ts) — event_changes hat aber nur eine
-- SELECT-Policy, kein INSERT für diese Rolle. Jedes UPDATE auf events,
-- inklusive des Status-Wechsels beim Veröffentlichen, ließ den Trigger
-- fehlschlagen und damit das gesamte UPDATE scheitern.
--
-- Zusätzlich: der Übergang draft -> scheduled selbst ist keine "Änderung",
-- die Nutzer je in ihrer Favoriten-/Detailansicht anders gesehen hätten
-- (ein Entwurf war nie sichtbar) — ohne Ausschluss hätte jede
-- Erstveröffentlichung einen irreführenden "Status geändert"-Eintrag im
-- "Kürzlich geändert"-Block erzeugt.
create or replace function log_event_changes() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Entwürfe sind nie nutzersichtbar — weder der Publish-Übergang selbst
  -- noch Bearbeitungen während des Entwurfsstatus sind eine "Änderung"
  -- im Sinne dieser Tabelle.
  if old.status = 'draft' then
    return new;
  end if;

  if new.start_datetime is distinct from old.start_datetime then
    insert into event_changes(event_id, field_name, old_value, new_value)
    values (new.id, 'start_datetime', old.start_datetime::text, new.start_datetime::text);
  end if;
  if new.venue_id is distinct from old.venue_id then
    insert into event_changes(event_id, field_name, old_value, new_value)
    values (new.id, 'venue_id', old.venue_id::text, new.venue_id::text);
  end if;
  if new.status is distinct from old.status then
    insert into event_changes(event_id, field_name, old_value, new_value)
    values (new.id, 'status', old.status, new.status);
  end if;
  if new.price_min is distinct from old.price_min or new.price_max is distinct from old.price_max then
    insert into event_changes(event_id, field_name, old_value, new_value)
    values (
      new.id, 'price',
      concat_ws('-', old.price_min, old.price_max),
      concat_ws('-', new.price_min, new.price_max)
    );
  end if;
  if new.remaining_tickets_status is distinct from old.remaining_tickets_status
    and new.remaining_tickets_status in ('few_left', 'sold_out') then
    insert into event_changes(event_id, field_name, old_value, new_value)
    values (new.id, 'remaining_tickets_status', old.remaining_tickets_status, new.remaining_tickets_status);
  end if;
  return new;
end;
$$;
