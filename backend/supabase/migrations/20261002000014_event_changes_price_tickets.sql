-- Phase A.1-Nachtrag (Task #15, docs/09-feature-expansion-plan.md): die
-- restlichen zwei Push-Anlässe aus notification_preferences brauchen eine
-- Änderungserkennung, die events_log_changes (20261002000011) noch nicht
-- abdeckte (nur start_datetime/venue_id/status). Ergänzt price_min/
-- price_max ("price_changes") und remaining_tickets_status
-- ("almost_sold_out").
create or replace function log_event_changes() returns trigger as $$
begin
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
  -- Nur der Übergang IN einen knappen/ausverkauften Zustand ist eine
  -- Nachricht wert ("fast ausverkauft") — der Rückweg (z.B. Kontingent
  -- nachträglich erhöht) ist keine dringliche Nutzer-Benachrichtigung.
  if new.remaining_tickets_status is distinct from old.remaining_tickets_status
    and new.remaining_tickets_status in ('few_left', 'sold_out') then
    insert into event_changes(event_id, field_name, old_value, new_value)
    values (new.id, 'remaining_tickets_status', old.remaining_tickets_status, new.remaining_tickets_status);
  end if;
  return new;
end;
$$ language plpgsql;
