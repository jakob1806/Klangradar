# Multi-City-Erweiterung — Schnittstellen für Client-Teams

Backend-only-Umsetzung (Migrationen `backend/supabase/migrations/
20261030000001` bis `20261030000009`, Admin unter `admin/src/app/
(dashboard)/regions`, `venues`). `ios-native/` wurde bewusst NICHT
angefasst, damit parallel ohne Merge-Konflikte weitergearbeitet werden
kann — dieses Dokument beschreibt den neuen Vertrag, den ein Client
konsumieren kann, sobald er selbst so weit ist.

Fünf Städte: München (`munich`), Berlin (`berlin`), Hamburg (`hamburg`),
Wien (`vienna`), Frankfurt am Main (`frankfurt`).

## Wichtigste Design-Entscheidung

Es gibt **keine neue `cities`-Tabelle**. Die bereits bestehende `regions`-
Tabelle (Land→Bundesland→Stadt-Hierarchie, siehe
`20260819000005_regions.sql`) wurde um die geforderten Stadt-Felder
ergänzt — sie ist an das bereits ausgelieferte iOS-Onboarding
(`profiles.preferred_region_id`) gebunden, eine zweite Tabelle wäre ein
Entitäts-Duplikat gewesen. Für den bequemen Read-Zugriff gibt es die View
`city_regions` (nur `type='city'`-Zeilen, mit aufgelöstem Bundesland-
Namen).

```sql
select * from city_regions order by sort_order;
-- id, slug, name_de, short_name_de, country_code, region_name,
-- timezone, latitude, longitude, default_zoom, search_radius_km,
-- hero_image_url, is_active, editorial_status, sort_order,
-- created_at, updated_at
```

`is_active` = für den Client sichtbar/wählbar. Alle vier neuen Städte
starten mit `is_active=false, editorial_status='soft_launch'` — sie
werden erst nach echten Erstimporten und redaktioneller Prüfung
freigeschaltet (Admin: `/regions`).

## Neue Spalten

| Tabelle | Spalte | Bedeutung |
|---|---|---|
| `venues` | `city_id uuid not null references regions(id)` | Operative Stadt-Zuordnung. `region_id` (alt) bleibt zusätzlich bestehen und zeigt aktuell auf denselben Wert — nicht entfernen, wird von bestehendem Code weiter gelesen. |
| `venues` | `city_area_id uuid references regions(id)` | Optionale zusätzliche Konzertregion für Nachbarort-Venues (siehe unten). |
| `events` | `city_id uuid references regions(id)` | Wird automatisch aus `venues.city_id` übernommen (Trigger), kann `null` sein bei fehlender Venue. |
| `events` | `city_override boolean not null default false` | `true` = Stadt wurde redaktionell fest gesetzt, wird NICHT mehr automatisch nachgezogen. |
| `sources` | `city_id uuid references regions(id)` | Alle Bestandsquellen wurden auf München gesetzt. |
| `editorial_collections` | `city_id uuid references regions(id)` | `null` = stadtübergreifend sichtbar. |
| `profiles` | `active_city_id uuid references regions(id)` | Aktive Stadt des Nutzers. Bestandsnutzer per Backfill auf München. |
| `profiles` | `favorite_city_ids uuid[]` | Optionale Schnellwechsel-Liste, rein additiv. |
| `profiles` | `city_selection_completed_at timestamptz` | Zeitstempel der ERSTEN expliziten Nutzer-Wahl. Ein künftiger erneuter Backfill darf `active_city_id` nur setzen, wenn dieses Feld `null` ist — Clients sollten es beim ersten expliziten Stadtwechsel setzen. |

**Automatik:** Ändert sich `venues.venue_id`→Stadt oder `venues.city_id`
direkt (Admin), ziehen alle nicht-`city_override`-Events automatisch mit
um (Trigger `sync_event_city_from_venue`/`cascade_venue_city_to_events`).

## Konzertregionen (Nachbarorte)

Generischer Mechanismus, keine Stadt hat Sonderlogik im Code:

- Tabelle `city_area_localities(city_id, locality_name, postal_code_prefix)`
  — z.B. `('Kronberg im Taunus', 'frankfurt')`.
- `venues.city_area_id` für Einzelfall-Ausnahmen.
- View `venues_in_city_region(venue_id, region_city_id)` fasst beides plus
  den direkten `city_id`-Fall zusammen — für Karten-/Venue-Listen-Queries
  gegen diese View joinen statt nur gegen `city_id`, damit z.B. eine
  Kronberg-Venue im Frankfurt-Feed erscheint.
- Funktion `suggest_city_id_for_locality(address_city, fallback_city_id)`
  — beim Anlegen einer neuen Venue automatisch die passende
  Konzertregion vorschlagen.

`venues.address_city` (die reale Ortsangabe, z.B. "Kronberg im Taunus")
bleibt davon unberührt.

## RPCs mit Stadt-Filter

Alle mit **München als Default** — ein Client, der den neuen Parameter
noch nicht mitschickt, sieht exakt das bisherige Verhalten:

```
search_all(q, result_limit, p_city_id default munich)
venues_with_latlng(p_city_id default munich)
popular_events(p_result_limit, p_city_id default munich)
```

`p_city_id => null` explizit übergeben = alle Städte (z.B. künftige
Übersichtskarte). Personen-/Ensemble-Ergebnisse in `search_all` bleiben
IMMER stadtübergreifend.

Neue RPCs (kein Default, `p_city_id` ist Pflichtparameter):

```
upcoming_events_by_city(p_city_id, p_result_limit=50, p_offset=0)
calendar_events_by_city(p_city_id, p_year, p_month)
events_today_by_city(p_city_id)
editorial_collections_by_city(p_city_id)
map_venues_by_city(p_city_id)            -- inkl. Konzertregion-Nachbarorte
followed_entity_events_by_city(p_user_id, p_city_id)
```

**Nicht angefasst:** `recommended_events`/`discovery_events` — beide sind
seit ihrer Einführung sehr groß/mehrfach umgebaut (zuletzt u.a.
`20261016000012/15/21/23`) geworden. Eine Stadt-Filterung dafür ist ein
eigener, fokussierter Folge-Schritt (siehe unten), kein Blind-Rewrite
ohne Testmöglichkeit.

Direkte PostgREST-Queries gegen `events`/`venues` (z.B. die bisherige
"kommende Events"-Abfrage) funktionieren unverändert weiter — `city_id`
ist einfach ein zusätzliches, indexiertes Filterfeld
(`events(city_id, start_datetime)` / `events(city_id, status,
start_datetime)` / `venues(city_id, name)`).

## Was noch NICHT erledigt ist

1. **`recommended_events`/`discovery_events`** brauchen noch `p_city_id`
   — bewusst zurückgestellt (siehe oben).
2. **Echte Veranstaltungsdaten** für Berlin/Hamburg/Wien/Frankfurt: es
   wurden `sources`-Zeilen für alle priorisierten Institutionen mit
   echten offiziellen URLs angelegt (`status='under_review'`), aber
   NICHT automatisch gescraped — das braucht eine echte
   Supabase-Umgebung mit laufenden Edge Functions, die in dieser Sandbox
   nicht verfügbar ist. Nächster Schritt: Admin → Datenquellen → pro
   Quelle prüfen/aktivieren, dann Ingestion anstoßen.
3. **Keine echten `venues`-Zeilen** für die neuen Städte wurden angelegt
   — das wären erfundene Adressen/Koordinaten gewesen. Venues entstehen
   über die Ingestion-Pipeline aus echten Quelldaten.
4. **Migrationen wurden NICHT gegen eine produktive Datenbank getestet**
   — kein Supabase-CLI/Docker in dieser Sandbox verfügbar. Vor dem Live-
   Deploy: `supabase db push` (oder Dashboard) in einer Staging-Umgebung
   verifizieren, insbesondere den `regions`-Slug-Rename (`muenchen` →
   `munich`) und die NOT-NULL-Backfills auf `venues.city_id`/
   `sources.city_id`.
5. **Qualitätsprüfung/Admin-UI**: Neue SQL-Views + `admin_quality_*`-RPCs
   (Abschnitt 10 der Aufgabenstellung) sind fertig, aber noch NICHT in
   die bestehende `/qualitaetspruefung`-Seite eingebunden (die aktuell
   nur die KI-gestützte Einzel-Entity-Audit-Pipeline anzeigt). Venue-
   Stadtwechsel mit Cascade-Warnung ist in `/venues` bereits eingebaut.
6. Keine flächendeckenden Stadt-Filter-Dropdowns auf den bestehenden
   Admin-Listenseiten (`/sources`, `/events`, `/venues`) — nur die neue
   Städte-Übersicht (`/regions`) und der Venue-Editor wurden angepasst.
