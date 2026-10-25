-- Erstellt von Claude Code (25.10.2026): Preiszeilen der Staatsoper
-- ("Preise H , € 88 / 77 / … Abo-…") aus bestehenden Beschreibungen lösen
-- und als Preis übernehmen (gleiche Regel wie _shared/priceInText.ts).
with parsed as (
  select id,
         regexp_replace(
           regexp_replace(description_de, '\s*(Preise?\s+[A-Z]{0,3}\s*,?\s*)?€\s*([0-9.,]+|-)(\s*/\s*([0-9.,]+|-))+(\s*<\s*30)?(\s+Abo[A-Za-zÄÖÜäöü-]*(\s+[A-Za-zÄÖÜäöü-]+){0,3})?', ' ', 'g'),
           '\s{2,}', ' ', 'g') as cleaned,
         (select array_agg(n::numeric) from regexp_matches(substring(description_de from '€\s*[0-9.,/ -]+'), '([0-9]+)', 'g') as m(n)) as prices
  from events
  where description_de ~ '€\s*([0-9.,]+|-)(\s*/\s*([0-9.,]+|-))+'
)
update events e
set description_de = nullif(btrim(p.cleaned), ''),
    price_min = coalesce(e.price_min, (select min(x) from unnest(p.prices) x where x > 0 and x < 1000)),
    price_max = coalesce(e.price_max, (select max(x) from unnest(p.prices) x where x > 0 and x < 1000))
from parsed p
where e.id = p.id;
