-- Veranstalter-Portal Phase 4: Verifizierung/Trust-System — kleinstmögliche
-- echte Scheibe aus dem ursprünglichen Konzept
-- ("unverified/claimed/verified/official"). Die ersten beiden Stufen
-- brauchen KEINE eigene Speicherung: "unverified" ist schlicht "keine
-- approved Zeile in entity_claims", "claimed" ist "mindestens eine approved
-- Zeile" — beides ist bereits aus entity_claims ableitbar (siehe
-- @/lib/entity-tables.ts resolveTrustLevels). Diese Tabelle speichert
-- ausschließlich die REDAKTIONELLE Zusatz-Einstufung "verified"/"official",
-- die über das reine Vorhandensein eines genehmigten Claims hinausgeht
-- (z.B. nach manueller Identitätsprüfung).
--
-- Bewusst eine eigene, schlanke Tabelle statt der Wiederverwendung von
-- persons/venues/ensembles.is_verified: diese Spalte bedeutet dort bereits
-- etwas anderes (redaktionelle Datenqualität der Stammdaten, unabhängig
-- davon, ob überhaupt ein Veranstalter-Claim existiert) — eine
-- Vermischung würde beide Konzepte durcheinanderbringen. organizers hat
-- ohnehin gar keine is_verified-Spalte.
create table entity_trust_overrides (
  entity_type text not null check (entity_type in ('organizer', 'venue', 'person', 'ensemble')),
  entity_id uuid not null,
  level text not null check (level in ('verified', 'official')),
  set_by uuid references profiles(id),
  set_at timestamptz not null default now(),
  primary key (entity_type, entity_id)
);

alter table entity_trust_overrides enable row level security;

-- Öffentlich lesbar (wie organizers/venues/persons/ensembles selbst) — ein
-- Trust-Badge ist erst nützlich, wenn ihn auch die konsumierenden Apps
-- lesen können. Deren tatsächliche Anzeige (Flutter/iOS/Android) ist NICHT
-- Teil dieser Phase, aber die Policy soll das nicht nachträglich blockieren.
create policy "Vertrauensstufen sind öffentlich lesbar" on entity_trust_overrides
  for select using (true);

create policy "Redaktion verwaltet Vertrauensstufen" on entity_trust_overrides
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());
