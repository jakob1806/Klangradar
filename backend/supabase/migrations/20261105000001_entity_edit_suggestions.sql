-- Veranstalter-Portal Phase 2: Profil-Bearbeitung geclaimter Entitäten
-- (Venue/Person/Ensemble/Institution) — "Vorschlag → Prüfung →
-- Veröffentlichung", analog zum bestehenden Event-Workflow, aber OHNE
-- direkten Schreibzugriff auf organizers/venues/persons/ensembles: anders
-- als bei eigenen Events (dort gehört die Zeile eindeutig dem Veranstalter)
-- ist eine geclaimte Stammdaten-Zeile weiterhin ein von der Redaktion
-- kuratiertes Objekt, das ggf. mehrere Veranstalter gleichzeitig verwalten
-- (siehe entity_claims-Migration) — jede Änderung muss deshalb geprüft
-- werden, bevor sie live geht.
--
-- Bewusst EIN generischer Vorschlag als jsonb-Patch statt einer Tabelle pro
-- Entitätstyp: die vier Zieltabellen haben unterschiedliche Spaltennamen für
-- vergleichbare Inhalte (persons.biography_de vs. organizers/venues/
-- ensembles.description_de), ein generischer Patch spart vier fast
-- identische Tabellen und vier fast identische Review-UIs.
create table entity_edit_suggestions (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('organizer', 'venue', 'person', 'ensemble')),
  entity_id uuid not null,
  user_id uuid not null references profiles(id) on delete cascade,
  proposed_changes jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index entity_edit_suggestions_status_idx on entity_edit_suggestions(status) where status = 'pending';
create index entity_edit_suggestions_entity_idx on entity_edit_suggestions(entity_type, entity_id);
-- Höchstens EIN offener Vorschlag gleichzeitig pro Nutzer/Entität — sonst
-- müsste die Redaktion raten, welcher von mehreren offenen, ggf.
-- widersprüchlichen Vorschlägen noch aktuell ist. Ein Nutzer mit bereits
-- offenem Vorschlag bekommt beim erneuten Versuch eine verständliche
-- Fehlermeldung (siehe actions.ts) statt einer rohen Constraint-Verletzung.
create unique index entity_edit_suggestions_one_pending_per_user_idx
  on entity_edit_suggestions(entity_type, entity_id, user_id)
  where status = 'pending';

alter table entity_edit_suggestions enable row level security;

create policy "Redaktion verwaltet Profiländerungsvorschläge" on entity_edit_suggestions
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

create policy "Nutzer sieht eigene Profiländerungsvorschläge" on entity_edit_suggestions
  for select using (auth.uid() = user_id);

-- Generalisierte Variante von has_approved_organizer_claim() (siehe
-- entity_claims-Migration) für beliebige entity_type-Werte — dort blieb die
-- Organizer-spezifische Funktion bewusst bestehen (von den events-Policies
-- referenziert), hier zusätzlich eine typ-generische Variante, weil
-- Profiländerungen für alle vier Claim-Typen möglich sein sollen.
create function has_approved_claim(p_entity_type text, p_entity_id uuid)
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
  );
$$;

create policy "Veranstalter schlägt Profiländerung für eigene Entität vor" on entity_edit_suggestions
  for insert
  with check (
    auth.uid() = user_id
    and status = 'pending'
    and has_approved_claim(entity_type, entity_id)
  );
