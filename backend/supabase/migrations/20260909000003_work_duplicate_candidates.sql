-- Werk-Duplikaterkennung: das Pendant zu duplicate_candidates (Events), aber
-- für works. Ausgelöst durch einen live beobachteten Fall im Komponisten-
-- Backfill-Testbatch (PR #101-Nachlauf): "Sinfonie Nr. 4 c-moll" wurde als
-- neues Werk angelegt statt gegen die bereits vorhandenen, leicht anders
-- betitelten Einträge "Sinfonie Nr. 4 c-moll 'Tragische'" / "Tragische"
-- desselben Events zu matchen — exaktes Normalisieren-und-Vergleichen (siehe
-- normalizeTitleForMatch in enrich-event-references/index.ts) erkennt
-- Titel-Varianten mit/ohne Beinamen nicht als dasselbe Werk.
--
-- Analog zum Events-Muster bewusst NICHT automatisch zusammengeführt (works
-- könnten trotz ähnlichen Titels wirklich unterschiedliche Stücke sein, z.B.
-- verschiedene Sätze oder Bearbeitungen) — nur zur redaktionellen Prüfung
-- vorgemerkt. work_a_id ist immer das ältere/bereits existierende Werk,
-- work_b_id das neu angelegte, das beim Zusammenführen gelöscht wird
-- (gleiche Konvention wie event_a_id/event_b_id).
create table work_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  work_a_id uuid references works(id) on delete cascade,
  work_b_id uuid references works(id) on delete cascade,
  similarity_score numeric(4,3),
  status text default 'pending',
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz default now()
);

create index work_duplicate_candidates_status_idx on work_duplicate_candidates(status) where status = 'pending';

alter table work_duplicate_candidates enable row level security;

create policy "Redaktion verwaltet Werk-Duplikate" on work_duplicate_candidates
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Fuzzy-Vorauswahl für enrich-event-references: exaktes Normalisieren-und-
-- Vergleichen (normalizeTitleForMatch in index.ts) matcht keine
-- Titel-Varianten mit/ohne Beinamen ("Sinfonie Nr. 4 c-moll" vs. "Sinfonie
-- Nr. 4 c-moll 'Tragische'"). Gleicher Stil/gleiche Konvention wie
-- find_matching_event/find_matching_venue (20260802000001).
create or replace function find_similar_works(
  p_title text,
  p_similarity_threshold numeric default 0.35,
  p_result_limit int default 5
)
returns table (
  id uuid,
  title text,
  composer_id uuid,
  catalog_number text,
  key_signature text,
  similarity numeric
)
language sql
stable
as $$
  select
    works.id,
    works.title,
    works.composer_id,
    works.catalog_number,
    works.key_signature,
    similarity(works.title, p_title) as similarity
  from works
  where similarity(works.title, p_title) >= p_similarity_threshold
  order by similarity(works.title, p_title) desc
  limit p_result_limit;
$$;
