-- Die vier bisher im Aufbau befindlichen Stadt-Ausgaben sind produktiv.
-- "live" ist der öffentliche redaktionelle Status im Stadtmodell; zusammen
-- mit is_active macht er die Stadt für Auswahl, Feed und Suche verfügbar.
with launched_cities as (
  select id
  from public.regions
  where type = 'city'
    and slug in ('berlin', 'hamburg', 'frankfurt', 'vienna')
)
update public.regions
set is_active = true,
    editorial_status = 'live'
where id in (select id from launched_cities);

-- Für die nun öffentlichen Stadt-Ausgaben bleiben keine redaktionellen
-- Entwürfe zurück. Vergangene Daten werden nicht verändert.
with launched_cities as (
  select id
  from public.regions
  where type = 'city'
    and slug in ('berlin', 'hamburg', 'frankfurt', 'vienna')
)
update public.events
set status = 'scheduled',
    review_status = 'published'
where city_id in (select id from launched_cities)
  and status = 'draft'
  and start_datetime >= now();

with launched_cities as (
  select id
  from public.regions
  where type = 'city'
    and slug in ('berlin', 'hamburg', 'frankfurt', 'vienna')
)
update public.editorial_collections
set is_published = true
where city_id in (select id from launched_cities)
  and is_published = false;
