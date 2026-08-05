-- Phase D.1 (docs/09-feature-expansion-plan.md), Nutzerwunsch Punkt 11:
-- "Höhepunkte der Woche, Debüts und selten gespielte Werke, kostenlose
-- Empfehlungen, thematische Sammlungen, Festivalübersichten, kurze
-- Werkeinführungen, 'Heute noch verfügbar'... Automatische Vorauswahl und
-- menschliche Kuratierung lassen sich gut kombinieren." Eigene Tabellen
-- statt festivals zweckzuentfremden — eine Sammlung ist thematisch/
-- redaktionell, kein reales Festival mit eigenem Veranstalter, und ein
-- Event kann in MEHREREN Sammlungen auftauchen (z.B. "Diese Woche" UND
-- "Für Einsteiger"), festivals.events-Zuordnung ist dagegen 1:1 über
-- events.festival_id.
create table editorial_collections (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  subtitle text,
  description_de text,
  cover_image_url text,
  -- Unpubliziert = Redaktion arbeitet noch dran, taucht in der App nicht
  -- auf (gleiches Prinzip wie events.status='draft').
  is_published boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table editorial_collection_events (
  collection_id uuid not null references editorial_collections(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  position int not null default 0,
  added_at timestamptz not null default now(),
  primary key (collection_id, event_id)
);
create index idx_editorial_collection_events_collection
  on editorial_collection_events(collection_id, position);

alter table editorial_collections enable row level security;
create policy "Veröffentlichte Sammlungen sind öffentlich lesbar"
  on editorial_collections for select
  using (is_published or is_admin_or_editor());
create policy "Redaktion verwaltet Sammlungen"
  on editorial_collections for all
  using (is_admin_or_editor()) with check (is_admin_or_editor());

alter table editorial_collection_events enable row level security;
create policy "Zuordnungen veröffentlichter Sammlungen sind lesbar"
  on editorial_collection_events for select
  using (
    is_admin_or_editor()
    or exists (
      select 1 from editorial_collections c
      where c.id = collection_id and c.is_published
    )
  );
create policy "Redaktion verwaltet Sammlung-Zuordnungen"
  on editorial_collection_events for all
  using (is_admin_or_editor()) with check (is_admin_or_editor());
