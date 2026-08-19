-- Neues Onboarding (Konzept: Anmeldung & Anmeldung/Onboarding) braucht mehr
-- Profildaten als bisher: Vor-/Nachname statt nur display_name, optional
-- Telefon/Adresse, eine AGB-/Datenschutz-Akzeptanz mit Zeitstempel+Version,
-- und eine bevorzugte Region für den Standort-Schritt-Fallback (aktuell nur
-- München aktiv, siehe regions.is_active aus 20260819000005_regions.sql).
-- Rein additiv — bestehende Policies auf profiles (Zeilen-basiert, nicht
-- spaltenbasiert) decken die neuen Spalten automatisch mit ab.
alter table profiles
  add column first_name text,
  add column last_name text,
  add column phone text,
  add column address text,
  add column terms_accepted_at timestamptz,
  add column terms_version text,
  add column preferred_region_id uuid references regions(id);
