-- Veranstalter-Portal Phase 3: Team & Rechte, kleinstmögliche echte Scheibe.
-- Phase 1 (entity_claims-Migration) kannte bewusst nur "hat Zugriff" oder
-- "hat keinen" und verwies granulare Rollen ausdrücklich hierher — dieser
-- Slice liefert genau die eine Unterscheidung, die neuen Nutzen stiftet:
-- Owner vs. Editor, damit ein bestehendes Team-Mitglied einen Kollegen
-- selbst freischalten kann, statt jedes Mal die Redaktion zu brauchen
-- ("Einladen durch bestehende Mitglieder statt nur Redaktions-Genehmigung",
-- siehe Phase-1-Plan). Volle Owner/Redaktion/Marketing-Abstufung aus dem
-- ursprünglichen Konzept bleibt spätere Erweiterung.
alter table entity_claims add column role text not null default 'editor' check (role in ('owner', 'editor'));

-- Backfill: alle HEUTE bereits genehmigten Claims werden 'owner' — das nimmt
-- niemandem etwas weg (jeder genehmigte Claim durfte bereits uneingeschränkt
-- Events/Profiländerungen einreichen), sondern erweitert nur um die neue
-- Owner-Fähigkeit, weitere Team-Mitglieder selbst freizuschalten.
update entity_claims set role = 'owner' where status = 'approved';

-- Analog zu has_approved_organizer_claim()/has_approved_claim() (siehe
-- entity_claims/entity_edit_suggestions-Migrationen), hier zusätzlich mit
-- role-Filter.
create function is_owner_of_entity(p_entity_type text, p_entity_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from entity_claims
    where entity_type = p_entity_type
      and entity_id = p_entity_id
      and user_id = auth.uid()
      and status = 'approved'
      and role = 'owner'
  );
$$;

-- Additiv zur bestehenden "Redaktion verwaltet Claims"-Policy (for all) —
-- ein Owner darf jetzt zusätzlich JEDEN Claim auf seiner eigenen Entität
-- verwalten: einen fremden pending-Claim direkt genehmigen/ablehnen (ohne
-- Redaktions-Umweg), oder die Rolle eines anderen Team-Mitglieds ändern.
-- Bewusst kein Recht, den eigenen Claim selbst zu bearbeiten — das ist
-- nirgends nötig (Owner-Status ändert sich nur über die Aktion eines
-- ANDEREN Owners oder der Redaktion) und würde sonst ungewollt erlauben,
-- sich selbst jederzeit erneut zu genehmigen, nachdem man abgelehnt wurde.
create policy "Owner verwaltet Team-Claims der eigenen Entität" on entity_claims
  for update
  using (is_owner_of_entity(entity_type, entity_id) and user_id <> auth.uid())
  with check (is_owner_of_entity(entity_type, entity_id) and user_id <> auth.uid());

-- Schutz vor einer Entität ohne jeden Owner (versehentlich durch einen
-- Owner, der den letzten anderen Owner degradiert/entfernt, oder durch die
-- Redaktion) — sieht sowohl OLD als auch NEW, deshalb Trigger statt RLS
-- with-check (wie bei prevent_organizer_status_change in der
-- entity_claims-Migration).
create function prevent_removing_last_owner() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.role = 'owner' and old.status = 'approved'
     and (new.role is distinct from 'owner' or new.status is distinct from 'approved')
     and not exists (
       select 1 from entity_claims
       where entity_type = old.entity_type
         and entity_id = old.entity_id
         and role = 'owner'
         and status = 'approved'
         and id <> old.id
     )
  then
    raise exception 'Mindestens ein Owner muss pro Entität bestehen bleiben.';
  end if;
  return new;
end;
$$;

create trigger entity_claims_guard_last_owner
  before update on entity_claims
  for each row
  execute function prevent_removing_last_owner();
