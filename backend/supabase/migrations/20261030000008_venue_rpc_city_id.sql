-- Multi-City-Erweiterung, Abschnitt 11 "Admin-Dashboard": Venue-
-- Stadtänderung. p_city_id als zusätzlicher Parameter MIT Default (analog
-- zum bestehenden Muster aus 20260825000001_entity_photo_uploads.sql für
-- p_photo_url) — bestehende Aufrufer bleiben kompatibel.
--
-- p_city_id default null bei create_venue bedeutet "automatisch anhand
-- der Ortsangabe vorschlagen" (siehe suggest_city_id_for_locality aus
-- 20261030000007), mit München als letztem Fallback — eine neu über das
-- Admin-Formular angelegte Venue bekommt so NIE eine leere Stadt, auch
-- wenn das Formular (noch) nicht aktualisiert wurde.
create or replace function create_venue(
  p_slug text,
  p_name text,
  p_description_de text,
  p_address_street text,
  p_address_zip text,
  p_address_city text,
  p_lat float,
  p_lng float,
  p_capacity int,
  p_website_url text,
  p_photo_url text default null,
  p_city_id uuid default null
)
returns venues
language plpgsql
as $$
declare
  v venues;
  v_city_id uuid;
begin
  v_city_id := coalesce(
    p_city_id,
    suggest_city_id_for_locality(p_address_city, (select id from regions where type = 'city' and slug = 'munich'))
  );

  insert into venues (
    slug, name, description_de, address_street, address_zip, address_city,
    location, capacity, website_url, photo_url, city_id
  )
  values (
    p_slug, p_name, p_description_de, p_address_street, p_address_zip,
    coalesce(p_address_city, 'München'), ST_MakePoint(p_lng, p_lat)::geography,
    p_capacity, p_website_url, p_photo_url, v_city_id
  )
  returning * into v;
  return v;
end;
$$;

-- update_venue: p_city_id default null bedeutet HIER "unverändert lassen"
-- (nicht "auf München zurücksetzen") — beim Bearbeiten einer bestehenden
-- Venue darf ein Admin-Formular, das den neuen Parameter noch nicht
-- mitschickt, niemals versehentlich die Stadt zurücksetzen. Der Cascade-
-- Effekt auf events.city_id passiert automatisch über den bestehenden
-- Trigger venues_cascade_city_to_events (20261030000002) — die
-- Admin-UI zeigt die betroffene Event-Anzahl VOR dem Speichern separat an
-- (siehe venue-form.tsx), diese RPC selbst warnt nicht, sie vollzieht nur.
create or replace function update_venue(
  p_id uuid,
  p_slug text,
  p_name text,
  p_description_de text,
  p_address_street text,
  p_address_zip text,
  p_address_city text,
  p_lat float,
  p_lng float,
  p_capacity int,
  p_website_url text,
  p_photo_url text default null,
  p_city_id uuid default null
)
returns venues
language plpgsql
as $$
declare
  v venues;
begin
  update venues set
    slug = p_slug,
    name = p_name,
    description_de = p_description_de,
    address_street = p_address_street,
    address_zip = p_address_zip,
    address_city = coalesce(p_address_city, address_city),
    location = ST_MakePoint(p_lng, p_lat)::geography,
    capacity = p_capacity,
    website_url = p_website_url,
    photo_url = p_photo_url,
    city_id = coalesce(p_city_id, city_id),
    updated_at = now()
  where id = p_id
  returning * into v;
  return v;
end;
$$;

drop function if exists venue_with_latlng(uuid);

create function venue_with_latlng(p_id uuid)
returns table (
  id uuid, slug text, name text, description_de text,
  address_street text, address_zip text, address_city text,
  lat float, lng float, capacity int, website_url text, photo_url text,
  city_id uuid
)
language sql
stable
as $$
  select
    v.id, v.slug, v.name, v.description_de,
    v.address_street, v.address_zip, v.address_city,
    ST_Y(v.location::geometry) as lat, ST_X(v.location::geometry) as lng,
    v.capacity, v.website_url, v.photo_url, v.city_id
  from venues v
  where v.id = p_id;
$$;

-- Für die Admin-Warnung "X Veranstaltungen werden mit umgezogen": Anzahl
-- der Events, die beim Stadtwechsel dieser Venue automatisch mitgezogen
-- würden (city_override=false, siehe Trigger).
create or replace function venue_event_count_for_city_change(p_venue_id uuid)
returns int
language sql
stable
as $$
  select count(*)::int from events where venue_id = p_venue_id and city_override = false;
$$;

grant execute on function venue_event_count_for_city_change(uuid) to authenticated;
