-- Phase A.2 (docs/09-feature-expansion-plan.md): Änderungstransparenz.
-- "Zuletzt geprüft" existiert bereits (last_verified_at), sagt aber nichts
-- darüber, WAS sich seitdem geändert hat. Ein Trigger statt Anwendungscode
-- an jeder einzelnen Schreibstelle (Ingestion, Admin-Dashboard, die diversen
-- enrich-*-Functions) — so wird JEDE Änderung an den nutzerrelevanten
-- Feldern erfasst, unabhängig davon, welcher Pfad sie geschrieben hat, ohne
-- dass jede künftige neue Schreibstelle daran denken müsste, selbst zu
-- protokollieren.
--
-- Bewusst nur die drei Felder mit dem größten Überraschungspotenzial für
-- Nutzer mit einer Favoriten-Verknüpfung (Beginn, Ort, Status — deckt
-- "verschoben"/"abgesagt"/"ausverkauft" ab). Programm-/Besetzungsänderungen
-- (event_works/event_participants) sind NICHT Teil dieser ersten Fassung —
-- eigener Ausbauschritt, siehe Plan-Dokument, da diese Tabellen kein
-- klassisches UPDATE sondern Insert/Delete-Diffing bräuchten.
create table event_changes (
  id bigint generated always as identity primary key,
  event_id uuid not null references events(id) on delete cascade,
  field_name text not null,
  old_value text,
  new_value text,
  changed_at timestamptz not null default now()
);
create index idx_event_changes_event on event_changes(event_id, changed_at desc);

alter table event_changes enable row level security;
-- Öffentlich lesbar wie die events-Tabelle selbst (siehe events-Policy) —
-- die App zeigt Änderungen direkt auf der Event-Detail-Seite an, kein
-- eingeloggter/redaktioneller Kontext nötig.
create policy "Änderungen sind öffentlich lesbar" on event_changes for select using (true);

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
  return new;
end;
$$ language plpgsql;

create trigger events_log_changes
  after update on events
  for each row execute function log_event_changes();
