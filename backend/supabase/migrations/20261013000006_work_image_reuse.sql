-- Werk-Bild-Verknüpfung: erlaubt, das Bild einer Veranstaltung für eine
-- andere Veranstaltung wiederzuverwenden, wenn dasselbe Werk aufgeführt
-- wird UND (a) derselbe/dieselbe Mitwirkende (Person oder Ensemble) an
-- derselben Venue auftritt, oder (b) dasselbe Ensemble unabhängig von der
-- Venue auftritt (Nutzervorgabe: Ensembles touren, Solist:innen/Dirigent:innen
-- nur an derselben Venue gleich aussehend gewertet).
--
-- Nur Veranstaltungen mit einem ECHTEN eigenen Bild (image_urls nicht leer)
-- kommen als Spender infrage — der bestehende Ensemble-/Personen-/Venue-
-- Fallback setzt bewusst nur primary_image_id, nie image_urls (siehe
-- ingest-source/write.ts attachCoverImage-Kommentar), genauso wie diese neue
-- Werk-Wiederverwendung selbst — dadurch können sich keine Fallback-Ketten
-- über mehrere Events hinweg von der ursprünglichen Quelle entfernen.

create table event_image_reuse (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  donor_event_id uuid references events(id) on delete set null,
  work_id uuid not null references works(id) on delete cascade,
  matched_entity_type text not null check (matched_entity_type in ('person', 'ensemble')),
  matched_entity_id uuid not null,
  matched_venue boolean not null,
  image_id uuid references images(id) on delete set null,
  status text not null default 'active' check (status in ('active', 'rejected')),
  created_at timestamptz not null default now(),
  unique (event_id, work_id)
);

create index event_image_reuse_status_idx on event_image_reuse (status, created_at desc);

alter table event_image_reuse enable row level security;

create policy "Redaktion liest Werk-Bild-Verknüpfungen" on event_image_reuse
  for select using (is_admin_or_editor());

create policy "Redaktion schreibt Werk-Bild-Verknüpfungen" on event_image_reuse
  for insert with check (is_admin_or_editor());

create policy "Redaktion aktualisiert Werk-Bild-Verknüpfungen" on event_image_reuse
  for update using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Findet den bestbewerteten Bild-Spender für eine Veranstaltung: dasselbe
-- Werk (event_works), plus entweder (a) ein gemeinsames Ensemble
-- (unabhängig von der Venue) oder (b) eine gemeinsame Person UND dieselbe
-- Venue. Nur Spender mit echtem eigenem Bild (image_urls nicht leer).
-- Sortierung: Venue-Treffer zuerst, dann die zeitlich jüngste Veranstaltung.
create or replace function find_work_image_donor(p_event_id uuid)
returns table (
  donor_event_id uuid,
  work_id uuid,
  matched_entity_type text,
  matched_entity_id uuid,
  matched_venue boolean,
  image_url text
)
language sql
stable
as $$
  with target as (
    select e.id, e.venue_id from events e where e.id = p_event_id
  ),
  target_works as (
    select ew.work_id from event_works ew where ew.event_id = p_event_id
  ),
  target_participants as (
    select ep.person_id, ep.ensemble_id from event_participants ep where ep.event_id = p_event_id
  ),
  candidates as (
    -- (a) gemeinsames Ensemble, Venue egal
    select
      ew.work_id,
      ev.id as donor_event_id,
      ev.image_urls[1] as image_url,
      (ev.venue_id = t.venue_id) as matched_venue,
      'ensemble'::text as matched_entity_type,
      ep.ensemble_id as matched_entity_id,
      ev.start_datetime
    from event_works ew
    join target_works tw on tw.work_id = ew.work_id
    join events ev on ev.id = ew.event_id and ev.id <> p_event_id
    cross join target t
    join event_participants ep on ep.event_id = ev.id and ep.ensemble_id is not null
    join target_participants tp on tp.ensemble_id = ep.ensemble_id
    where ev.image_urls is not null and array_length(ev.image_urls, 1) > 0

    union all

    -- (b) gemeinsame Person, nur bei gleicher Venue
    select
      ew.work_id,
      ev.id as donor_event_id,
      ev.image_urls[1] as image_url,
      true as matched_venue,
      'person'::text as matched_entity_type,
      ep.person_id as matched_entity_id,
      ev.start_datetime
    from event_works ew
    join target_works tw on tw.work_id = ew.work_id
    join events ev on ev.id = ew.event_id and ev.id <> p_event_id
    cross join target t
    join event_participants ep on ep.event_id = ev.id and ep.person_id is not null
    join target_participants tp on tp.person_id = ep.person_id
    where ev.venue_id = t.venue_id
      and ev.image_urls is not null and array_length(ev.image_urls, 1) > 0
  )
  select work_id, donor_event_id, matched_entity_type, matched_entity_id, matched_venue, image_url
  from candidates
  order by matched_venue desc, start_datetime desc nulls last
  limit 1;
$$;
