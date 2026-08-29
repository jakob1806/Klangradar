-- Veranstalter-Portal Phase 1: Selbstbedienungs-Claiming für bestehende
-- organizers/venues/persons/ensembles-Zeilen + eigene Event-Einreichung.
-- Bewusst EINE Tabelle statt "claim request" + "permission grant" getrennt
-- — sobald status='approved', IST die Zeile der Berechtigungsnachweis
-- (siehe has_approved_organizer_claim() weiter unten), kein zweiter Ort
-- zum Verwalten nötig. Polymorph über entity_type/entity_id statt vier
-- FK-Spalten, weil entity_candidates.entity_type (person/ensemble/
-- organizer) Venues bislang gar nicht kennt und wir hier alle vier
-- gleich behandeln wollen.
--
-- Nutzerwunsch: "Team- und Rechte-System, damit mehrere Personen Zugriff
-- haben können" — deshalb bewusst KEINE unique(entity_type, entity_id)
-- where status='approved': mehrere unabhängig genehmigte Claims auf
-- dieselbe Entität sind erlaubt, jeder genehmigte Claim berechtigt zum
-- Verwalten. Granulare Rollen INNERHALB eines Teams (Owner vs. Redaktion
-- vs. Marketing) bleiben einer späteren "Team & Rechte"-Phase vorbehalten.
create table entity_claims (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('organizer', 'venue', 'person', 'ensemble')),
  entity_id uuid not null,
  user_id uuid not null references profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  justification text,
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  -- Verhindert doppelte Claims derselben Person auf dieselbe Entität
  -- (mehrfaches Klicken, erneuter Versuch nach Ablehnung wäre sonst ein
  -- zweiter offener Claim statt eines erkennbaren Duplikats).
  unique (entity_type, entity_id, user_id)
);

create index entity_claims_status_idx on entity_claims(status) where status = 'pending';
create index entity_claims_user_idx on entity_claims(user_id);
create index entity_claims_entity_idx on entity_claims(entity_type, entity_id);

-- Selbstbedienungs-Neuanlage einer Institution braucht eine Möglichkeit,
-- "das war MEINE Neuanlage" fälschungssicher in RLS zu prüfen — ohne diese
-- Spalte könnte niemand unterscheiden, ob ein Nutzer eine echte Neuanlage
-- sofort selbst genehmigt oder sich per INSERT einen approved-Claim auf
-- eine FREMDE, bereits bestehende Institution erschleicht.
alter table organizers add column created_by uuid references profiles(id);

alter table entity_claims enable row level security;

-- Redaktion sieht/verwaltet alles (Review-Queue), exakt dasselbe Muster
-- wie bei allen anderen "Redaktion verwaltet X"-Policies im Projekt.
create policy "Redaktion verwaltet Claims" on entity_claims
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Nutzer sieht nur eigene Claims (additiv zur Redaktions-Policy — Postgres
-- RLS-Policies sind permissive und werden pro Command-Typ ODER-verknüpft).
create policy "Nutzer sieht eigene Claims" on entity_claims
  for select using (auth.uid() = user_id);

-- Normalfall: Claim auf eine BESTEHENDE Entität landet immer als 'pending'
-- in der Redaktions-Prüfung — kann vom Client nicht umgangen werden, weil
-- status hier hart auf 'pending' erzwungen ist.
create policy "Nutzer beantragt Claim auf bestehende Entität" on entity_claims
  for insert
  with check (auth.uid() = user_id and status = 'pending');

-- Ausnahme: eine SELBST neu angelegte Institution braucht keine Prüfung,
-- der Claim darf sofort 'approved' sein — aber NUR, wenn organizers.created_by
-- nachweislich diesem Nutzer gehört. created_by kann seinerseits nur über
-- die neue Insert-Policy auf organizers (siehe unten) mit auth.uid()
-- gesetzt worden sein, das Sicherheitsargument reicht also bis zur
-- Organizer-Neuanlage selbst durch.
create policy "Ersteller-Claim auf eigene neue Institution ist sofort genehmigt" on entity_claims
  for insert
  with check (
    auth.uid() = user_id
    and status = 'approved'
    and entity_type = 'organizer'
    and exists (select 1 from organizers o where o.id = entity_id and o.created_by = auth.uid())
  );

-- Selbstbedienungs-Neuanlage einer Institution: bisher durfte NUR Redaktion
-- (is_admin_or_editor()) in organizers schreiben ("Redaktion verwaltet
-- Organizers", 20260715000013). Additive Policy, ausschließlich INSERT,
-- ausschließlich für die eigene Zeile (created_by = auth.uid()) — Editieren
-- bestehender Felder bleibt bewusst Redaktion vorbehalten (Profil-
-- Bearbeitung geclaimter Entitäten ist explizit spätere Phase).
create policy "Veranstalter legt eigene Institution an" on organizers
  for insert
  with check (created_by = auth.uid());

-- Helper im Stil von is_admin_or_editor()/is_admin() (20260715000013) —
-- SECURITY DEFINER, damit die Policy nicht selbstreferenzierend auf die
-- RLS-geschützte entity_claims-Tabelle zugreifen muss.
create function has_approved_organizer_claim(p_organizer_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from entity_claims
    where entity_type = 'organizer'
      and entity_id = p_organizer_id
      and user_id = auth.uid()
      and status = 'approved'
  );
$$;

-- Additive Policies auf events (bestehende "Redaktion verwaltet Events"/
-- "Veröffentlichte Events sind lesbar" bleiben unverändert stehen).
create policy "Veranstalter sieht eigene Events" on events
  for select using (organizer_id is not null and has_approved_organizer_claim(organizer_id));

create policy "Veranstalter legt eigene Events an" on events
  for insert
  with check (
    organizer_id is not null
    and has_approved_organizer_claim(organizer_id)
    and status = 'draft'
  );

create policy "Veranstalter bearbeitet eigene Events" on events
  for update
  using (organizer_id is not null and has_approved_organizer_claim(organizer_id))
  with check (organizer_id is not null and has_approved_organizer_claim(organizer_id));

-- Nutzerwunsch: "Veröffentlicht bleiben, Änderung sofort sichtbar" — ein
-- Veranstalter darf ein bereits geprüftes eigenes Event frei weiter
-- bearbeiten (z.B. Preis korrigieren), OHNE dass es dafür erneut in die
-- Redaktionsprüfung zurückfällt. Gleichzeitig darf ein Veranstalter NIE
-- selbst den Veröffentlichungsstatus ändern (ein Entwurf darf sich nicht
-- selbst freischalten, ein Event nicht selbst absagen/verschieben) — das
-- lässt sich mit einer reinen RLS with-check-Klausel nicht ausdrücken
-- (die sieht nur die NEUE Zeile, nicht "wie war status vorher"), deshalb
-- per Trigger statt Policy: verwirft jede status-Änderung durch
-- Nicht-Redaktion, lässt alle anderen Feldänderungen unangetastet durch.
create function prevent_organizer_status_change() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin_or_editor() and new.status is distinct from old.status then
    new.status := old.status;
  end if;
  return new;
end;
$$;

create trigger events_organizer_status_guard
  before update on events
  for each row
  execute function prevent_organizer_status_change();
