-- Fundament für die grundlegende Überarbeitung der Datenanreicherung/
-- Detailseiten (Nutzeranfrage: "Quellen, Abrufdatum und Vertrauensbewertung
-- pro Datenfeld speichern" + "alle Namen normalisieren und Dubletten/
-- Schreibvarianten zusammenführen; Aliasnamen erhalten, damit Suchen
-- weiterhin funktionieren"). Beide Anforderungen sind Querschnittsthemen
-- für ALLE Entitätstypen (Events/Venues/Personen/Ensembles/Werke/
-- Festivals/Organizer), daher zwei generische Tabellen statt pro Tabelle
-- eigene Spalten — analog zum bestehenden Muster von "images"
-- (20260819000003_images_and_tags.sql), das schon Provenienz für Bilder
-- separat von der Kernentität hält, statt sie in Spalten auf venues/
-- persons/... zu quetschen.

-- ============================================================================
-- field_provenance: pro (Entität, Feld) die zuletzt bekannte Quelle,
-- wann sie abgerufen wurde und wie vertrauenswürdig sie eingestuft ist.
-- ============================================================================
-- Bewusst EIN aktueller Stand pro Feld, keine volle Versionshistorie —
-- die Nutzeranfrage verlangt "wiederkehrend aktualisieren", nicht eine
-- Änderungshistorie; ein Unique-Index auf (entity_type, entity_id,
-- field_name) macht ein Upsert bei jeder Neu-Recherche zum Normalfall.
create table field_provenance (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (
    entity_type in ('event', 'venue', 'person', 'ensemble', 'work', 'festival', 'organizer')
  ),
  entity_id uuid not null,
  -- Spaltenname der Kernentität (z.B. "biography_de", "accessibility",
  -- "program_id") ODER ein logischer Feldname für Daten, die über
  -- mehrere Tabellen verteilt sind (z.B. "cast" für event_participants,
  -- "program" für program_id/program_items). Bewusst text statt Enum:
  -- neue Felder sollen ohne Migration ergänzbar sein.
  field_name text not null,
  source_url text,
  source_name text,
  retrieved_at timestamptz not null default now(),
  confidence text not null default 'unknown'
    check (confidence in ('confirmed', 'likely', 'uncertain', 'unknown')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (entity_type, entity_id, field_name)
);
create index field_provenance_entity_idx on field_provenance (entity_type, entity_id);

alter table field_provenance enable row level security;
create policy "Provenienzdaten sind öffentlich lesbar"
  on field_provenance for select using (true);
create policy "Redaktion verwaltet Provenienzdaten"
  on field_provenance for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- ============================================================================
-- entity_aliases: Schreibvarianten/Alternativnamen, damit z.B.
-- "Tschaikowski"/"Tchaikovsky"/"Tschaikowsky" konsistent einer einzigen
-- Personen-Zeile zugeordnet bleiben (Suche, künftige Fuzzy-Merge-Checks),
-- statt wie bisher versehentlich als eigene Dublette angelegt zu werden
-- (siehe die manuell zusammengeführten Duplikate von 2026-07-26: Fazil/
-- Fazıl Say, zwei Anton-Rubinstein-Zeilen, Dmitri/Dmitrij Schostakowitsch).
-- ============================================================================
create table entity_aliases (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (
    entity_type in ('person', 'ensemble', 'venue', 'organizer', 'festival')
  ),
  entity_id uuid not null,
  alias text not null,
  created_at timestamptz not null default now(),
  unique (entity_type, entity_id, alias)
);
create index entity_aliases_lookup_idx on entity_aliases (entity_type, lower(alias));

alter table entity_aliases enable row level security;
create policy "Aliasnamen sind öffentlich lesbar"
  on entity_aliases for select using (true);
create policy "Redaktion verwaltet Aliasnamen"
  on entity_aliases for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- ============================================================================
-- Komponisten-Epoche (Nutzeranfrage: "musikalische Epoche" pro Komponist).
-- Auf persons statt einer separaten "composers"-Tabelle — Komponisten sind
-- in diesem Schema bereits persons mit roles enthält 'composer'
-- (works.composer_id verweist auf persons.id), keine eigene Entität.
-- ============================================================================
alter table persons add column era text;

-- ============================================================================
-- Event: bereinigter Anzeigetitel vs. Quellentitel (Nutzeranfrage: "ein
-- aussagekräftiger, bereinigter Anzeigetitel plus ursprünglicher
-- Quellentitel"). "title" bleibt das, was tatsächlich angezeigt wird
-- (kein Breaking Change für bestehenden Lesepfad) — source_title hält
-- den unveränderten Originaltitel aus der Quelle, nur befüllt, wenn er
-- sich vom bereinigten Titel unterscheidet.
-- ============================================================================
alter table events add column source_title text;

-- Gattung für Werke (Nutzeranfrage: "wichtigsten Gattungen" bei
-- Komponisten, "Gattung" bei Werken) — bisher nur indirekt über
-- description_de erfassbar.
alter table works add column genre text;
