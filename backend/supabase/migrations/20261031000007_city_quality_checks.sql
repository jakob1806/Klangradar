-- Multi-City-Erweiterung, Abschnitt 10 "Datenqualität".
--
-- Rein deterministische, lesende Views statt einer Erweiterung der
-- KI-gestützten audit-entity-Pipeline (die bewusst pro Einzel-Entität
-- läuft und Tokens/Zeit kostet) — Stadt-Konsistenzprüfungen sind
-- strukturelle SQL-Fragen, keine KI-Bewertungsfragen. "Sichere
-- automatische Entscheidungen" gibt es hier nur eine (Venue-Stadtwechsel
-- kaskadiert automatisch auf Events, siehe
-- 20261031000002_city_id_venues_events_sources.sql) — alles unten ist
-- bewusst nur ein PRÜFBARER VORSCHLAG (reine Leseansicht), kein
-- automatischer Fix: Venue-Duplikate zusammenzuführen oder eine Stadt
-- händisch zu korrigieren bleibt eine redaktionelle Entscheidung.

-- Venue ohne Stadt: kann durch die NOT NULL-Constraint auf
-- venues.city_id eigentlich nicht mehr vorkommen, bleibt aber als
-- Sicherheitsnetz (z.B. falls die Constraint je über eine Migration
-- entfernt würde) und als einheitliche Anlaufstelle für die Admin-Seite.
create or replace view quality_venues_missing_city as
select v.id as venue_id, v.slug, v.name, v.address_city
from venues v
where v.city_id is null;

-- Event ohne Stadt: eine nicht (mehr) auflösbare Venue, oder eine Venue,
-- deren eigene city_id fehlt (sollte durch obige Constraint nicht
-- vorkommen, siehe oben).
create or replace view quality_events_missing_city as
select e.id as event_id, e.slug, e.title, e.venue_id, e.start_datetime
from events e
where e.city_id is null;

-- Event-Stadt widerspricht der Venue-Stadt: kann nur bei explizitem
-- city_override=true entstehen (siehe Trigger sync_event_city_from_venue)
-- — hier als PRÜFBARER Vorschlag sichtbar machen, ob der Override
-- wirklich beabsichtigt war (z.B. Gastspiel) oder ein Fehler ist.
create or replace view quality_event_venue_city_mismatch as
select e.id as event_id, e.slug, e.title, e.city_id as event_city_id,
       v.id as venue_id, v.name as venue_name, v.city_id as venue_city_id
from events e
join venues v on v.id = e.venue_id
where e.city_override and e.city_id is distinct from v.city_id;

-- Stadt widerspricht den Koordinaten: Venue liegt weiter als ihr
-- search_radius_km (mit 50% Toleranz für Konzertregion-Nachbarorte, siehe
-- Abschnitt 5) vom Stadtzentrum entfernt.
create or replace view quality_venue_city_coordinate_mismatch as
select
  v.id as venue_id, v.slug, v.name, v.address_city,
  r.slug as city_slug, r.name as city_name,
  round((ST_Distance(v.location, ST_MakePoint(r.longitude, r.latitude)::geography) / 1000)::numeric, 1) as distance_km,
  r.search_radius_km
from venues v
join regions r on r.id = v.city_id and r.type = 'city'
where r.latitude is not null
  and ST_Distance(v.location, ST_MakePoint(r.longitude, r.latitude)::geography)
      > coalesce(r.search_radius_km, 40) * 1000 * 1.5;

-- Events außerhalb des Suchradius (dieselbe Prüfung, aber auf Event-Ebene
-- für die "Auffällige Events"-Liste, ohne über eine widersprüchliche
-- Venue-Stadt zu laufen — z.B. eine korrekt zugeordnete Venue, deren
-- Koordinaten schlicht fehlerhaft erfasst wurden).
create or replace view quality_events_outside_radius as
select e.id as event_id, e.slug, e.title, e.start_datetime, m.venue_id, m.city_slug, m.distance_km, m.search_radius_km
from quality_venue_city_coordinate_mismatch m
join events e on e.venue_id = m.venue_id
where e.status = 'scheduled' and e.start_datetime >= now();

-- Venue-Duplikate INNERHALB derselben Stadt (Namensähnlichkeit via
-- pg_trgm, bereits als Extension für idx_venues_name_trgm aktiv, siehe
-- 20260715000003_venues.sql). Gleichnamige Venues in VERSCHIEDENEN
-- Städten werden hier bewusst NICHT als Duplikat geführt (Auftrag:
-- "gleichnamige Venues in verschiedenen Städten nicht automatisch
-- zusammenführen") — daher der city_id-Gleichheits-Join.
create or replace view quality_duplicate_venues_per_city as
select
  a.id as venue_id_a, a.name as name_a,
  b.id as venue_id_b, b.name as name_b,
  a.city_id,
  similarity(a.name, b.name) as name_similarity
from venues a
join venues b on b.city_id = a.city_id and a.id < b.id
where similarity(a.name, b.name) > 0.6
order by name_similarity desc;

-- Quellen ohne Stadt: kann durch NOT NULL auf sources.city_id (siehe
-- 20261031000002) nicht mehr vorkommen (Backfill setzt alles auf
-- München), bleibt aber als konsistente Anlaufstelle für die Admin-Seite
-- falls die Spalte künftig nullable würde bzw. für zukünftige Importe,
-- die die Spalte versehentlich leer lassen.
create or replace view quality_sources_missing_city as
select s.id as source_id, s.name, s.type, s.url
from sources s
where s.city_id is null;

-- Quelle mit ungewöhnlich wenigen/plötzlich keinen kommenden Events:
-- aktive Quelle, aber 0 zukünftige Events UND schon mindestens einmal
-- erfolgreich gelaufen (unterscheidet "nie erfolgreich importiert" nicht
-- von "war produktiv, ist jetzt plötzlich leer" — beides ist prüfenswert,
-- aber unterschiedlich dringend, daher has_run als eigenes Feld statt nur
-- ein einzelnes Flag).
create or replace view quality_sources_low_yield as
select
  s.id as source_id, s.name, s.type, s.city_id, s.status,
  s.last_success_at,
  count(e.id) filter (where e.status = 'scheduled' and e.start_datetime >= now()) as upcoming_event_count
from sources s
left join events e on e.source_id = s.id
where s.status = 'active'
group by s.id, s.name, s.type, s.city_id, s.status, s.last_success_at
having count(e.id) filter (where e.status = 'scheduled' and e.start_datetime >= now()) = 0
   and s.last_success_at is not null;

-- Views selbst haben kein RLS und ziehen nur die (öffentlichen) Policies
-- ihrer Basistabellen (venues/events/sources sind bereits öffentlich
-- lesbar) — das reicht hier NICHT, das sind interne Redaktionsansichten.
-- Kein select-Grant an anon/authenticated; stattdessen SECURITY DEFINER-
-- Wrapper-Funktionen mit explizitem is_admin_or_editor()-Check, analog
-- zum bestehenden Muster in 20260715000013_row_level_security.sql.
revoke all on
  quality_venues_missing_city,
  quality_events_missing_city,
  quality_event_venue_city_mismatch,
  quality_venue_city_coordinate_mismatch,
  quality_events_outside_radius,
  quality_duplicate_venues_per_city,
  quality_sources_missing_city,
  quality_sources_low_yield
from anon, authenticated;

create or replace function admin_quality_venues_missing_city()
returns setof quality_venues_missing_city language sql security definer set search_path = public stable as $$
  select * from quality_venues_missing_city where is_admin_or_editor();
$$;
create or replace function admin_quality_events_missing_city()
returns setof quality_events_missing_city language sql security definer set search_path = public stable as $$
  select * from quality_events_missing_city where is_admin_or_editor();
$$;
create or replace function admin_quality_event_venue_city_mismatch()
returns setof quality_event_venue_city_mismatch language sql security definer set search_path = public stable as $$
  select * from quality_event_venue_city_mismatch where is_admin_or_editor();
$$;
create or replace function admin_quality_venue_city_coordinate_mismatch()
returns setof quality_venue_city_coordinate_mismatch language sql security definer set search_path = public stable as $$
  select * from quality_venue_city_coordinate_mismatch where is_admin_or_editor();
$$;
create or replace function admin_quality_events_outside_radius()
returns setof quality_events_outside_radius language sql security definer set search_path = public stable as $$
  select * from quality_events_outside_radius where is_admin_or_editor();
$$;
create or replace function admin_quality_duplicate_venues_per_city()
returns setof quality_duplicate_venues_per_city language sql security definer set search_path = public stable as $$
  select * from quality_duplicate_venues_per_city where is_admin_or_editor();
$$;
create or replace function admin_quality_sources_missing_city()
returns setof quality_sources_missing_city language sql security definer set search_path = public stable as $$
  select * from quality_sources_missing_city where is_admin_or_editor();
$$;
create or replace function admin_quality_sources_low_yield()
returns setof quality_sources_low_yield language sql security definer set search_path = public stable as $$
  select * from quality_sources_low_yield where is_admin_or_editor();
$$;

grant execute on function
  admin_quality_venues_missing_city(),
  admin_quality_events_missing_city(),
  admin_quality_event_venue_city_mismatch(),
  admin_quality_venue_city_coordinate_mismatch(),
  admin_quality_events_outside_radius(),
  admin_quality_duplicate_venues_per_city(),
  admin_quality_sources_missing_city(),
  admin_quality_sources_low_yield()
to authenticated;

-- Helfer für Ingestion/Admin: schlägt city_id für eine neue Venue anhand
-- ihres Ortsnamens vor (Konzertregion-Zuordnung, siehe
-- city_area_localities), ohne Stadt-Sonderfälle im Anwendungscode.
create or replace function suggest_city_id_for_locality(p_address_city text, p_fallback_city_id uuid)
returns uuid
language sql
stable
as $$
  select coalesce(
    (select city_id from city_area_localities where locality_name = p_address_city limit 1),
    p_fallback_city_id
  );
$$;

grant execute on function suggest_city_id_for_locality(text, uuid) to authenticated;
