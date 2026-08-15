-- Genres werden redaktionell erweitert und dürfen deshalb nicht länger auf
-- die historische genre_type-Enum-Liste beschränkt sein.
alter table genres alter column slug type text using slug::text;

-- Frühere KI-Imports speicherten Instrumentlisten teilweise als JSON-Text.
-- In der Datenbank ein lesbares Format herstellen; Native behandelt alte
-- Cachewerte zusätzlich defensiv.
update persons
set instrument = (
  select string_agg(upper(left(value, 1)) || substring(value from 2), ' · ' order by ordinality)
  from jsonb_array_elements_text(instrument::jsonb) with ordinality as item(value, ordinality)
)
where instrument ~ '^\s*\[\s*"';
