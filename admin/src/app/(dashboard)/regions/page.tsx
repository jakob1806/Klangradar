import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { getActiveCityFilter } from "@/lib/city-filter";
import { toggleRegionActive } from "./actions";

export const dynamic = "force-dynamic";

const TYPE_LABEL: Record<string, string> = {
  country: "Land",
  state: "Bundesland",
  city: "Stadt",
};

const EDITORIAL_STATUS_LABEL: Record<string, string> = {
  planned: "Geplant",
  soft_launch: "Im Aufbau",
  live: "Öffentlich",
};

interface RegionRow {
  id: string;
  type: string;
  name: string;
  slug: string;
  parent_id: string | null;
  is_active: boolean;
  editorial_status: string | null;
}

interface CityMetrics {
  venueCount: number;
  upcomingEventCount: number;
  sourcesActive: number;
  sourcesTotal: number;
  duplicateSuspects: number;
  venueImageCoverage: { total: number; withImage: number };
  ensembleImageCoverage: { total: number; withImage: number };
}

export default async function RegionsPage() {
  const supabase = await createClient();
  const cityFilter = await getActiveCityFilter();
  const [
    { data: regions, error },
    { data: venues },
    { data: ensembles },
    { data: images },
    { data: allCityRows },
    { count: eventsMissingCity },
  ] = await Promise.all([
    supabase
      .from("regions")
      .select("id, type, name, slug, parent_id, is_active, editorial_status")
      .order("type")
      .returns<RegionRow[]>(),
    supabase.from("venues").select("id, city_id"),
    // Ensembles haben kein eigenes city_id — Stadtbezug kommt (wie überall
    // sonst in diesem Katalog) über das home_venue_id → venues.city_id.
    supabase.from("ensembles").select("id, home_venue_id"),
    supabase
      .from("images")
      .select("origin_type, origin_id")
      .in("origin_type", ["venue", "ensemble"])
      .neq("license_status", "rejected"),
    supabase
      .from("city_regions")
      .select("id, slug, name_de, short_name_de, editorial_status, sort_order")
      .order("sort_order")
      .returns<{ id: string; slug: string; name_de: string; short_name_de: string | null; editorial_status: string; sort_order: number }[]>(),
    // Global statt pro Stadt: ein Event ohne Venue hat per Definition auch
    // keine Stadt (city_id folgt der Venue) — eine einzige Kennzahl statt
    // derselben Abfrage N-mal pro Stadt-Kachel zu wiederholen.
    supabase.from("events").select("id", { count: "exact", head: true }).is("venue_id", null),
  ]);

  const venueCountByRegion = new Map<string, number>();
  const venueCityById = new Map<string, string>();
  for (const v of venues ?? []) {
    if (!v.city_id) continue;
    venueCountByRegion.set(v.city_id, (venueCountByRegion.get(v.city_id) ?? 0) + 1);
    venueCityById.set(v.id, v.city_id);
  }

  const ensembleCityById = new Map<string, string>();
  const ensembleCountByRegion = new Map<string, number>();
  for (const e of ensembles ?? []) {
    const cityId = e.home_venue_id ? venueCityById.get(e.home_venue_id) : undefined;
    if (!cityId) continue;
    ensembleCityById.set(e.id, cityId);
    ensembleCountByRegion.set(cityId, (ensembleCountByRegion.get(cityId) ?? 0) + 1);
  }

  const venuesWithImageByRegion = new Map<string, Set<string>>();
  const ensemblesWithImageByRegion = new Map<string, Set<string>>();
  for (const img of images ?? []) {
    const byRegion = img.origin_type === "venue" ? venuesWithImageByRegion : ensemblesWithImageByRegion;
    const cityById = img.origin_type === "venue" ? venueCityById : ensembleCityById;
    const cityId = cityById.get(img.origin_id);
    if (!cityId) continue;
    const set = byRegion.get(cityId) ?? new Set<string>();
    set.add(img.origin_id);
    byRegion.set(cityId, set);
  }
  const byId = new Map((regions ?? []).map((r) => [r.id, r]));
  // "Alle Städte" zeigt wie bisher jede Stadt-Kachel; bei einer aktiven
  // Stadtauswahl im globalen Umschalter nur noch deren eigene Kachel.
  const cityRows = cityFilter.cityId
    ? (allCityRows ?? []).filter((c) => c.id === cityFilter.cityId)
    : allCityRows;

  // Kennzahlen pro Stadt (Abschnitt 11): kommende Events, Quellenstatus,
  // Duplikatverdacht. Parallel pro Stadt statt einer riesigen Sammel-Query,
  // damit eine einzelne Fehlerquelle (z.B. eine Stadt ohne Daten) nicht die
  // ganze Seite zum Absturz bringt.
  const metricsEntries = await Promise.all(
    (cityRows ?? []).map(async (city): Promise<[string, CityMetrics]> => {
      const [{ count: upcomingEventCount }, { count: sourcesActive }, { count: sourcesTotal }, { data: dupes }] =
        await Promise.all([
          supabase
            .from("events")
            .select("id", { count: "exact", head: true })
            .eq("city_id", city.id)
            .eq("status", "scheduled")
            .gte("start_datetime", new Date().toISOString()),
          supabase.from("sources").select("id", { count: "exact", head: true }).eq("city_id", city.id).eq("status", "active"),
          supabase.from("sources").select("id", { count: "exact", head: true }).eq("city_id", city.id),
          supabase.rpc("admin_quality_duplicate_venues_per_city").eq("city_id", city.id),
        ]);

      return [
        city.id,
        {
          venueCount: venueCountByRegion.get(city.id) ?? 0,
          upcomingEventCount: upcomingEventCount ?? 0,
          sourcesActive: sourcesActive ?? 0,
          sourcesTotal: sourcesTotal ?? 0,
          duplicateSuspects: dupes?.length ?? 0,
          venueImageCoverage: {
            total: venueCountByRegion.get(city.id) ?? 0,
            withImage: venuesWithImageByRegion.get(city.id)?.size ?? 0,
          },
          ensembleImageCoverage: {
            total: ensembleCountByRegion.get(city.id) ?? 0,
            withImage: ensemblesWithImageByRegion.get(city.id)?.size ?? 0,
          },
        },
      ];
    }),
  );
  const metricsByCity = new Map(metricsEntries);

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Städte & Regionen</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Jede Konzertregion mit Kennzahlen. Eine Stadt muss hier aktiv geschaltet sein, bevor sie für die App
        freigegeben wird.
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Regionen nicht laden: {error.message}</p>}

      {!!eventsMissingCity && (
        <p className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900">
          {eventsMissingCity} Veranstaltung{eventsMissingCity === 1 ? "" : "en"} ohne Venue (und damit ohne Stadt) —
          siehe Qualitätsprüfung.
        </p>
      )}

      <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        {(cityRows ?? []).map((city) => {
          const region = byId.get(city.id);
          const m = metricsByCity.get(city.id);
          return (
            <div key={city.id} className="rounded-xl border border-black/[0.06] bg-white p-5 shadow-sm">
              <div className="flex items-center justify-between">
                <p className="text-base font-semibold text-neutral-900">{city.name_de}</p>
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                    region?.is_active ? "bg-emerald-100 text-emerald-700" : "bg-neutral-100 text-neutral-500"
                  }`}
                >
                  {region?.is_active ? "Aktiv" : "Inaktiv"}
                </span>
              </div>
              <p className="mt-0.5 text-xs text-neutral-400">
                /{city.slug} · {EDITORIAL_STATUS_LABEL[city.editorial_status] ?? city.editorial_status}
              </p>

              <dl className="mt-4 grid grid-cols-2 gap-y-2 text-sm">
                <dt className="text-neutral-500">Venues</dt>
                <dd className="text-right font-medium text-neutral-900">{m?.venueCount ?? 0}</dd>
                <dt className="text-neutral-500">Kommende Events</dt>
                <dd className="text-right font-medium text-neutral-900">{m?.upcomingEventCount ?? 0}</dd>
                <dt className="text-neutral-500">Quellen (aktiv/gesamt)</dt>
                <dd className="text-right font-medium text-neutral-900">
                  {m?.sourcesActive ?? 0}/{m?.sourcesTotal ?? 0}
                </dd>
                <dt className="text-neutral-500">Duplikatverdacht</dt>
                <dd className={`text-right font-medium ${m && m.duplicateSuspects > 0 ? "text-amber-700" : "text-neutral-900"}`}>
                  {m?.duplicateSuspects ?? 0}
                </dd>
                <dt className="text-neutral-500">Venue-Bilder</dt>
                <dd className="text-right font-medium text-neutral-900">
                  {m?.venueImageCoverage.withImage ?? 0}/{m?.venueImageCoverage.total ?? 0}
                </dd>
                <dt className="text-neutral-500">Ensemble-Bilder</dt>
                <dd className="text-right font-medium text-neutral-900">
                  {m?.ensembleImageCoverage.withImage ?? 0}/{m?.ensembleImageCoverage.total ?? 0}
                </dd>
              </dl>

              <div className="mt-4 flex items-center justify-between border-t border-neutral-100 pt-3">
                <a
                  href={`/qualitaetspruefung?city=${city.slug}`}
                  className="text-xs font-medium text-neutral-600 hover:text-neutral-900"
                >
                  Qualitätsprüfung für {city.short_name_de ?? city.name_de} →
                </a>
                {region && (
                  <ConfirmButton
                    action={toggleRegionActive.bind(null, region.id, !region.is_active)}
                    confirmMessage={
                      region.is_active ? `"${city.name_de}" deaktivieren?` : `"${city.name_de}" aktivieren?`
                    }
                    label={region.is_active ? "Deaktivieren" : "Aktivieren"}
                    pendingLabel="Speichere…"
                    className="text-xs font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                  />
                )}
              </div>
            </div>
          );
        })}
      </div>

      <h2 className="mt-10 text-sm font-semibold text-neutral-700">Alle Regionen (Hierarchie)</h2>
      {!error && (
        <div className="mt-3 flex flex-col gap-2">
          {regions?.length ? (
            regions.map((region) => {
              const parent = region.parent_id ? byId.get(region.parent_id) : null;
              return (
                <div
                  key={region.id}
                  className="flex items-center justify-between rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm"
                >
                  <div>
                    <p className="text-sm font-medium text-neutral-900">
                      {region.name}
                      <span className="ml-2 text-xs text-neutral-400">
                        {TYPE_LABEL[region.type] ?? region.type}
                        {parent ? ` · in ${parent.name}` : ""}
                      </span>
                    </p>
                    <p className="mt-1 text-xs text-neutral-500">
                      /{region.slug} · {venueCountByRegion.get(region.id) ?? 0} Venues
                    </p>
                  </div>
                  <div className="flex items-center gap-4">
                    <span
                      className={`text-xs font-medium ${region.is_active ? "text-emerald-700" : "text-neutral-400"}`}
                    >
                      {region.is_active ? "Aktiv" : "Inaktiv"}
                    </span>
                    <ConfirmButton
                      action={toggleRegionActive.bind(null, region.id, !region.is_active)}
                      confirmMessage={
                        region.is_active
                          ? `"${region.name}" deaktivieren?`
                          : `"${region.name}" aktivieren?`
                      }
                      label={region.is_active ? "Deaktivieren" : "Aktivieren"}
                      pendingLabel="Speichere…"
                      className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
                    />
                  </div>
                </div>
              );
            })
          ) : (
            <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine Regionen angelegt.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
