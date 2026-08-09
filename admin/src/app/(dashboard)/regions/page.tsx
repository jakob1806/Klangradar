import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { toggleRegionActive } from "./actions";

export const dynamic = "force-dynamic";

const TYPE_LABEL: Record<string, string> = {
  country: "Land",
  state: "Bundesland",
  city: "Stadt",
};

interface RegionRow {
  id: string;
  type: string;
  name: string;
  slug: string;
  parent_id: string | null;
  is_active: boolean;
}

export default async function RegionsPage() {
  const supabase = await createClient();
  const [{ data: regions, error }, { data: venues }] = await Promise.all([
    supabase.from("regions").select("id, type, name, slug, parent_id, is_active").order("type").returns<RegionRow[]>(),
    supabase.from("venues").select("region_id"),
  ]);

  const venueCountByRegion = new Map<string, number>();
  for (const v of venues ?? []) {
    if (!v.region_id) continue;
    venueCountByRegion.set(v.region_id, (venueCountByRegion.get(v.region_id) ?? 0) + 1);
  }
  const byId = new Map((regions ?? []).map((r) => [r.id, r]));

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Regionen</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Geografische Hierarchie (Land → Bundesland → Stadt). Eine Region muss hier aktiv geschaltet sein, bevor sie
        künftig für die App freigegeben wird.
      </p>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Regionen nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-2">
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
