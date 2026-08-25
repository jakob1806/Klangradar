import { createClient } from "@/lib/supabase/server";

// Rein deterministische, SQL-basierte Stadt-Konsistenzchecks (siehe
// 20261030000007_city_quality_checks.sql) — bewusst getrennt von der
// KI-gestützten entity_audit_flags-Pipeline der übrigen Tabs auf dieser
// Seite: das sind strukturelle Fragen (Stadt fehlt/widerspricht sich),
// keine KI-Bewertungsfragen. Alle admin_quality_*-RPCs sind bereits
// serverseitig auf is_admin_or_editor() beschränkt (SECURITY DEFINER).
interface VenueMissingCity {
  venue_id: string;
  slug: string;
  name: string;
  address_city: string;
}
interface EventMissingCity {
  event_id: string;
  slug: string;
  title: string;
  venue_id: string | null;
  start_datetime: string;
}
interface EventVenueCityMismatch {
  event_id: string;
  slug: string;
  title: string;
  venue_id: string;
  venue_name: string;
}
interface CoordinateMismatch {
  venue_id: string;
  slug: string;
  name: string;
  address_city: string;
  city_slug: string;
  distance_km: number;
  search_radius_km: number;
}
interface DuplicateVenue {
  venue_id_a: string;
  name_a: string;
  venue_id_b: string;
  name_b: string;
  name_similarity: number;
}
interface SourceMissingCity {
  source_id: string;
  name: string;
  type: string;
  url: string;
}
interface SourceLowYield {
  source_id: string;
  name: string;
  type: string;
  status: string;
  last_success_at: string | null;
}

function Section({
  title,
  count,
  emptyLabel,
  children,
}: {
  title: string;
  count: number;
  emptyLabel: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-xl border border-neutral-200 bg-white p-4">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-neutral-900">{title}</p>
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${
            count > 0 ? "bg-amber-100 text-amber-800" : "bg-neutral-100 text-neutral-400"
          }`}
        >
          {count}
        </span>
      </div>
      {count > 0 ? (
        <ul className="mt-2 flex flex-col gap-1 text-xs text-neutral-600">{children}</ul>
      ) : (
        <p className="mt-2 text-xs text-neutral-400">{emptyLabel}</p>
      )}
    </div>
  );
}

export async function CityQualitySection() {
  const supabase = await createClient();
  const [
    { data: rawVenuesMissingCity },
    { data: rawEventsMissingCity },
    { data: rawCityMismatches },
    { data: rawCoordinateMismatches },
    { data: rawDuplicateVenues },
    { data: rawSourcesMissingCity },
    { data: rawSourcesLowYield },
  ] = await Promise.all([
    supabase.rpc("admin_quality_venues_missing_city"),
    supabase.rpc("admin_quality_events_missing_city"),
    supabase.rpc("admin_quality_event_venue_city_mismatch"),
    supabase.rpc("admin_quality_venue_city_coordinate_mismatch"),
    supabase.rpc("admin_quality_duplicate_venues_per_city"),
    supabase.rpc("admin_quality_sources_missing_city"),
    supabase.rpc("admin_quality_sources_low_yield"),
  ]);
  // supabase-js kennt die Rückgabeform frisch angelegter RPCs nicht aus
  // generierten Datenbank-Typen (kein Codegen gegen eine echte Remote-DB
  // in dieser Sandbox möglich) — Cast statt .returns<T[]>(), gleiches
  // Muster wie admin_list_users in users/page.tsx.
  const venuesMissingCity = rawVenuesMissingCity as VenueMissingCity[] | null;
  const eventsMissingCity = rawEventsMissingCity as EventMissingCity[] | null;
  const cityMismatches = rawCityMismatches as EventVenueCityMismatch[] | null;
  const coordinateMismatches = rawCoordinateMismatches as CoordinateMismatch[] | null;
  const duplicateVenues = rawDuplicateVenues as DuplicateVenue[] | null;
  const sourcesMissingCity = rawSourcesMissingCity as SourceMissingCity[] | null;
  const sourcesLowYield = rawSourcesLowYield as SourceLowYield[] | null;

  return (
    <div className="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2">
      <Section title="Venues ohne Stadt" count={venuesMissingCity?.length ?? 0} emptyLabel="Alle Venues haben eine Stadt.">
        {venuesMissingCity?.map((v) => (
          <li key={v.venue_id}>
            <a href={`/venues/${v.venue_id}`} className="text-[#0071e3] hover:underline">
              {v.name}
            </a>{" "}
            — {v.address_city}
          </li>
        ))}
      </Section>

      <Section title="Events ohne Stadt" count={eventsMissingCity?.length ?? 0} emptyLabel="Alle Events haben eine Stadt.">
        {eventsMissingCity?.map((e) => (
          <li key={e.event_id}>
            <a href={`/events/${e.event_id}`} className="text-[#0071e3] hover:underline">
              {e.title}
            </a>
          </li>
        ))}
      </Section>

      <Section
        title="Event-Stadt widerspricht Venue-Stadt"
        count={cityMismatches?.length ?? 0}
        emptyLabel="Keine Widersprüche (nur bei redaktionellem Stadt-Override möglich)."
      >
        {cityMismatches?.map((m) => (
          <li key={m.event_id}>
            <a href={`/events/${m.event_id}`} className="text-[#0071e3] hover:underline">
              {m.title}
            </a>{" "}
            — Venue {m.venue_name}
          </li>
        ))}
      </Section>

      <Section
        title="Stadt widerspricht Koordinaten"
        count={coordinateMismatches?.length ?? 0}
        emptyLabel="Alle Venues liegen im plausiblen Radius ihrer Stadt."
      >
        {coordinateMismatches?.map((m) => (
          <li key={m.venue_id}>
            <a href={`/venues/${m.venue_id}`} className="text-[#0071e3] hover:underline">
              {m.name}
            </a>{" "}
            — {m.distance_km} km von {m.city_slug} (Radius {m.search_radius_km} km)
          </li>
        ))}
      </Section>

      <Section
        title="Mögliche Venue-Duplikate (dieselbe Stadt)"
        count={duplicateVenues?.length ?? 0}
        emptyLabel="Keine Duplikatverdachtsfälle."
      >
        {duplicateVenues?.map((d) => (
          <li key={`${d.venue_id_a}-${d.venue_id_b}`}>
            <a href={`/venues/${d.venue_id_a}`} className="text-[#0071e3] hover:underline">
              {d.name_a}
            </a>{" "}
            ↔{" "}
            <a href={`/venues/${d.venue_id_b}`} className="text-[#0071e3] hover:underline">
              {d.name_b}
            </a>{" "}
            ({Math.round(d.name_similarity * 100)}% ähnlich)
          </li>
        ))}
      </Section>

      <Section
        title="Quellen ohne Stadt"
        count={sourcesMissingCity?.length ?? 0}
        emptyLabel="Alle Quellen haben eine Stadt."
      >
        {sourcesMissingCity?.map((s) => (
          <li key={s.source_id}>
            <a href={`/sources/${s.source_id}`} className="text-[#0071e3] hover:underline">
              {s.name}
            </a>
          </li>
        ))}
      </Section>

      <Section
        title="Aktive Quellen ohne kommende Events"
        count={sourcesLowYield?.length ?? 0}
        emptyLabel="Alle aktiven Quellen liefern kommende Events."
      >
        {sourcesLowYield?.map((s) => (
          <li key={s.source_id}>
            <a href={`/sources/${s.source_id}`} className="text-[#0071e3] hover:underline">
              {s.name}
            </a>
          </li>
        ))}
      </Section>
    </div>
  );
}
