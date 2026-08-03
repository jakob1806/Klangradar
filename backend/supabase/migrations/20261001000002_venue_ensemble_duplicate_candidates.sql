-- Abschnitt 6/E der Gesamtüberarbeitung: die zwei echten Lücken im
-- Entity-Matching — für Events/Personen/Werke gibt es längst eine
-- Dedup-Review-Queue (duplicate_candidates/person_duplicate_candidates/
-- work_duplicate_candidates), für Venues/Ensembles nicht. Konkreter Anlass
-- aus einer früheren Nutzermeldung: "Gasteig HP8"/"Isarphilharmonie" und
-- "Nationaltheater"/"Bayerische Staatsoper" erscheinen doppelt auf der
-- Karte — beides ist dieselbe physische Location unter zwei Namen
-- (Umbenennung/offizieller vs. Alltagsname), NICHT über Namens-Trigram-
-- Ähnlichkeit auffindbar (die Namen haben keine gemeinsame Zeichenkette).
-- find_matching_venue() (Ingestion-Zeitpunkt, 20260802000001) hilft hier
-- nicht — das prüft nur beim Neuanlegen, nicht rückwirkend über den
-- gesamten Bestand.
--
-- Deshalb zwei Signale statt nur Namens-Trigram:
--   1. räumliche Nähe (PostGIS ST_DWithin auf venues.location) — der
--      tatsächliche Bug-Fall.
--   2. Namens-Trigram wie bei find_matching_venue/find_matching_ensemble,
--      als Fallback für Tipp-/Schreibvarianten am selben Ort.
-- Ensembles haben keine Adresse — dort bleibt Namens-Trigram das einzige
-- Signal (wie find_matching_ensemble, gleicher Schwellenwert 0.5).

create table venue_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  venue_a_id uuid references venues(id) on delete set null,
  venue_b_id uuid references venues(id) on delete set null,
  similarity_score numeric(4,3),
  match_reason text not null check (match_reason in ('proximity', 'name_similarity')),
  status text default 'pending',
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz default now()
);

-- ON DELETE SET NULL statt der ursprünglichen Default-Vorgabe (RESTRICT) —
-- der beim Zusammenführen von Events live beobachtete FK-Bug
-- (duplicate_candidates_event_b_id_fkey, siehe PR-Historie) entsteht genau
-- dann, wenn diese Zeile zuerst auf status='merged' gesetzt wird und danach
-- die verworfene Venue gelöscht wird, während die Zeile noch auf sie
-- verweist. Hier von vornherein vermieden statt erst nach demselben Fehler
-- nachträglich zu reparieren.
create unique index venue_duplicate_candidates_pending_pair_idx
  on venue_duplicate_candidates (least(venue_a_id, venue_b_id), greatest(venue_a_id, venue_b_id))
  where status = 'pending';
create index venue_duplicate_candidates_status_idx on venue_duplicate_candidates(status) where status = 'pending';

alter table venue_duplicate_candidates enable row level security;
create policy "Redaktion verwaltet Venue-Duplikate" on venue_duplicate_candidates
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

create table ensemble_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  ensemble_a_id uuid references ensembles(id) on delete set null,
  ensemble_b_id uuid references ensembles(id) on delete set null,
  similarity_score numeric(4,3),
  status text default 'pending',
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz default now()
);

create unique index ensemble_duplicate_candidates_pending_pair_idx
  on ensemble_duplicate_candidates (least(ensemble_a_id, ensemble_b_id), greatest(ensemble_a_id, ensemble_b_id))
  where status = 'pending';
create index ensemble_duplicate_candidates_status_idx on ensemble_duplicate_candidates(status) where status = 'pending';

alter table ensemble_duplicate_candidates enable row level security;
create policy "Redaktion verwaltet Ensemble-Duplikate" on ensemble_duplicate_candidates
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Drei-Bänder-Konvention (Abschnitt 6: "auto/manuell/ablehnen" statt eines
-- einzelnen Schwellenwerts), hier zentral dokumentiert statt verteilt:
--   >= auto-Schwelle:    würde automatisch zusammengeführt (NICHT
--                        implementiert — Abschnitt 6 verbietet ausdrücklich
--                        automatische Merges ohne Autorisierung; hier
--                        bewusst nie erreicht, beide Bänder unten landen in
--                        der Review-Queue).
--   review-Schwelle..<auto: zur redaktionellen Prüfung vorgemerkt (dieser
--                        Job).
--   < review-Schwelle:   kein Kandidat, wird ignoriert.
-- Da Abschnitt 6 automatisches Zusammenführen für Venues/Ensembles nicht
-- vorsieht, ist die "auto"-Schwelle hier rein dokumentarisch (kein Wert
-- erreicht sie technisch) — beide Signale münden immer in der Review-Queue,
-- nie in einem automatischen Merge.
create or replace function detect_venue_duplicate_candidates(
  p_proximity_meters numeric default 60,
  p_name_similarity_threshold numeric default 0.6
)
returns int
language plpgsql
as $$
declare
  v_inserted int := 0;
begin
  with proximity_pairs as (
    select a.id as a_id, b.id as b_id,
      round((1 - st_distance(a.location, b.location) / p_proximity_meters)::numeric, 3) as score
    from venues a
    join venues b on a.id < b.id
    where st_dwithin(a.location, b.location, p_proximity_meters)
  ),
  name_pairs as (
    select a.id as a_id, b.id as b_id, round(similarity(a.name, b.name)::numeric, 3) as score
    from venues a
    join venues b on a.id < b.id
    where similarity(a.name, b.name) >= p_name_similarity_threshold
  ),
  candidates as (
    select a_id, b_id, score, 'proximity' as reason from proximity_pairs
    union all
    select a_id, b_id, score, 'name_similarity' as reason from name_pairs
    where not exists (select 1 from proximity_pairs pp where pp.a_id = name_pairs.a_id and pp.b_id = name_pairs.b_id)
  )
  insert into venue_duplicate_candidates (venue_a_id, venue_b_id, similarity_score, match_reason)
  select c.a_id, c.b_id, c.score, c.reason
  from candidates c
  where not exists (
    select 1 from venue_duplicate_candidates existing
    where least(existing.venue_a_id, existing.venue_b_id) = least(c.a_id, c.b_id)
      and greatest(existing.venue_a_id, existing.venue_b_id) = greatest(c.a_id, c.b_id)
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create or replace function detect_ensemble_duplicate_candidates(
  p_name_similarity_threshold numeric default 0.5
)
returns int
language plpgsql
as $$
declare
  v_inserted int := 0;
begin
  insert into ensemble_duplicate_candidates (ensemble_a_id, ensemble_b_id, similarity_score)
  select a.id, b.id, round(similarity(a.name, b.name)::numeric, 3)
  from ensembles a
  join ensembles b on a.id < b.id
  where similarity(a.name, b.name) >= p_name_similarity_threshold
    and not exists (
      select 1 from ensemble_duplicate_candidates existing
      where least(existing.ensemble_a_id, existing.ensemble_b_id) = least(a.id, b.id)
        and greatest(existing.ensemble_a_id, existing.ensemble_b_id) = greatest(a.id, b.id)
    )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

-- Wöchentlich statt stündlich wie bei den Personen-Duplikaten — Venues/
-- Ensembles entstehen viel seltener als neue Personen, eine engere Taktung
-- brächte nichts. Reine SQL-Funktionen, kein net.http_post/Edge-Function-
-- Umweg nötig (anders als resolve-person-duplicates, das KI-Bestätigung
-- braucht) — direkter cron.schedule-Aufruf.
select cron.schedule(
  'venue-duplicate-detection',
  '0 3 * * 0',
  $$ select detect_venue_duplicate_candidates(); $$
);
select cron.schedule(
  'ensemble-duplicate-detection',
  '0 3 * * 0',
  $$ select detect_ensemble_duplicate_candidates(); $$
);
