-- Staatsoper-URLs haben die stabile Form /stuecke/<produktion>/<termin>.
-- Produktionsbild und Werkprogramm gelten für alle Termine derselben
-- Produktion; die Besetzung ausdrücklich nicht (sie ist terminabhängig).
with production_events as (
  select e.*,
    substring(e.website_url from 'staatsoper\.de/(?:stuecke|produktionen)/([^/]+)') as production_key
  from events e
  where e.website_url ilike '%staatsoper.de/%'
    and e.start_datetime >= now()
), production_images as (
  select distinct on (production_key) production_key, image_urls
  from production_events
  where production_key is not null and cardinality(image_urls) > 0
  order by production_key, start_datetime
)
update events e
set image_urls = pi.image_urls
from production_images pi
where cardinality(e.image_urls) = 0
  and substring(e.website_url from 'staatsoper\.de/(?:stuecke|produktionen)/([^/]+)') = pi.production_key
  and pi.image_urls is not null;

with production_events as (
  select e.id, e.start_datetime,
    substring(e.website_url from 'staatsoper\.de/(?:stuecke|produktionen)/([^/]+)') as production_key
  from events e
  where e.website_url ilike '%staatsoper.de/%'
    and e.start_datetime >= now()
), source_event as (
  select distinct on (pe.production_key) pe.production_key, pe.id
  from production_events pe
  where exists (select 1 from event_works ew where ew.event_id = pe.id)
  order by pe.production_key, pe.start_datetime
), target_event as (
  select pe.id, se.id as source_id
  from production_events pe
  join source_event se using (production_key)
  where not exists (select 1 from event_works ew where ew.event_id = pe.id)
)
insert into event_works (event_id, work_id, position, after_intermission)
select te.id, ew.work_id, ew.position, ew.after_intermission
from target_event te
join event_works ew on ew.event_id = te.source_id
on conflict do nothing;
