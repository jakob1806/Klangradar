-- Veranstalter-Portal "Institution/Venue/Person/Ensemble beanspruchen":
-- Live-Vorschläge sollen ein Miniaturbild neben dem Namen zeigen (Venue/
-- Ensemble eckig, Person rund -- siehe Claim-Suche im Portal). Die vier
-- find_matching_*-RPCs lieferten bislang kein Bild, deshalb hier neu
-- angelegt (Rückgabetyp ändert sich, "create or replace" allein reicht
-- dafür nicht) mit einer zusätzlichen photo_url-Spalte. Restliche Logik
-- unverändert aus der jeweils aktuellsten Fassung übernommen.

drop function if exists find_matching_organizer(text, numeric, int);
create function find_matching_organizer(
  p_name text,
  p_similarity_threshold numeric default 0.5,
  p_result_limit int default 3
)
returns table (id uuid, name text, similarity numeric, photo_url text)
language sql
stable
as $$
  select
    organizers.id,
    organizers.name,
    similarity(organizers.name, p_name) as similarity,
    organizers.logo_url as photo_url
  from organizers
  where similarity(organizers.name, p_name) >= p_similarity_threshold
  order by similarity(organizers.name, p_name) desc
  limit p_result_limit;
$$;

drop function if exists find_matching_venue(text, numeric, int);
create function find_matching_venue(
  p_name text,
  p_similarity_threshold numeric default 0.4,
  p_result_limit int default 3
)
returns table (id uuid, name text, similarity numeric, photo_url text)
language sql
stable
as $$
  select
    venues.id,
    venues.name,
    similarity(venues.name, p_name) as similarity,
    venues.photo_url
  from venues
  where similarity(venues.name, p_name) >= p_similarity_threshold
  order by similarity(venues.name, p_name) desc
  limit p_result_limit;
$$;

drop function if exists find_matching_ensemble(text, numeric, int);
create function find_matching_ensemble(
  p_name text,
  p_similarity_threshold numeric default 0.5,
  p_result_limit int default 3
)
returns table (id uuid, name text, similarity numeric, photo_url text)
language sql
stable
as $$
  select
    ensembles.id,
    ensembles.name,
    similarity(ensembles.name, p_name) as similarity,
    ensembles.photo_url
  from ensembles
  where similarity(ensembles.name, p_name) >= p_similarity_threshold
  order by similarity(ensembles.name, p_name) desc
  limit p_result_limit;
$$;

-- find_matching_person hat in der aktuellsten Fassung
-- (20261011000013_prefer_canonical_composer_names.sql) eine deutlich
-- aufwendigere Kandidaten-/Kanonisierungslogik für Komponisten. Statt sie
-- hier zu duplizieren, bleibt die bestehende Funktion unangetastet und wird
-- nur um photo_url erweitert -- direkt aus persons gejoint, da id im
-- Ergebnis eindeutig ist.
create or replace function find_matching_person_with_photo(
  p_name text,
  p_similarity_threshold numeric default 0.5,
  p_result_limit int default 3
)
returns table (id uuid, full_name text, similarity numeric, photo_url text)
language sql
stable
as $$
  select m.id, m.full_name, m.similarity, p.photo_url
  from find_matching_person(p_name, p_similarity_threshold, p_result_limit) m
  join persons p on p.id = m.id;
$$;
