import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import {
  BioResearchBar,
  BioRowCheckbox,
  BioSelectAllCheckbox,
  BioSelectMissingButton,
  BioSelectionProvider,
  BioStatusBadge,
} from "@/components/bio-select";
import { ImageStatusBadge } from "@/components/image-status-badge";
import { ListThumbnail } from "@/components/list-thumbnail";
import { ListPagination, ListToolbar, VerifiedBadge, ilikePattern, listRange, listRowClass, listTheadClass, listThClass, readListParams } from "@/components/entity-list";
import { getActiveCityFilter } from "@/lib/city-filter";
import { bulkDeleteVenues, bulkSetVenuesVerified } from "./actions";

export const dynamic = "force-dynamic";

interface VenueRow {
  id: string;
  name: string;
  address_city: string;
  capacity: number | null;
  is_verified: boolean;
  description_de: string | null;
  photo_url: string | null;
  events: { count: number }[];
}

const FILTERS = [
  { key: "all", label: "Alle" },
  { key: "no_photo", label: "Ohne Foto" },
  { key: "no_bio", label: "Ohne Beschreibung" },
  { key: "unverified", label: "Ungeprüft" },
  { key: "no_capacity", label: "Ohne Kapazität" },
];
const SORTS = [
  { key: "name", label: "Name A–Z" },
  { key: "city", label: "Stadt" },
  { key: "updated", label: "Zuletzt geändert" },
];

// Erweiterung (Claude Code, 29.10.2026): Suche, Filter, Sortierung und
// Seiten serverseitig (components/entity-list.tsx); Stadtfilter wie bisher.
export default async function VenuesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = readListParams(await searchParams, FILTERS, SORTS);
  const supabase = await createClient();
  const cityFilter = await getActiveCityFilter();
  let query = supabase
    .from("venues")
    .select("id, name, address_city, capacity, is_verified, description_de, photo_url, events(count)", { count: "exact" });
  if (cityFilter.cityId) query = query.eq("city_id", cityFilter.cityId);
  if (params.q) query = query.or(`name.ilike.${ilikePattern(params.q)},address_city.ilike.${ilikePattern(params.q)}`);
  if (params.filter === "no_photo") query = query.is("photo_url", null);
  if (params.filter === "no_bio") query = query.is("description_de", null);
  if (params.filter === "unverified") query = query.eq("is_verified", false);
  if (params.filter === "no_capacity") query = query.is("capacity", null);
  query =
    params.sort === "city"
      ? query.order("address_city").order("name")
      : params.sort === "updated"
        ? query.order("updated_at", { ascending: false, nullsFirst: false })
        : query.order("name");
  const [from, to] = listRange(params);
  const { data: rows, error, count } = await query.range(from, to).returns<VenueRow[]>();
  const data = rows ?? [];
  const total = count ?? 0;

  const missingBioIds = data.filter((v) => !v.description_de).map((v) => v.id);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Venues</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Veranstaltungsorte redaktionell pflegen.
          </p>
        </div>
        <Link
          href="/venues/new"
          className="rounded-lg bg-[#2D2A6E] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#38358a]"
        >
          Neu anlegen
        </Link>
      </div>

      {error && (
        <p className="mt-6 text-sm text-amber-700">Konnte Venues nicht laden: {error.message}</p>
      )}

      {!error && (
        <BioSelectionProvider>
          <div className="mt-6">
            <ListToolbar basePath="/venues" params={params} filters={FILTERS} sorts={SORTS} total={total} searchPlaceholder="Name oder Stadt suchen …">
              <BioSelectMissingButton ids={missingBioIds} />
            </ListToolbar>
            <BioResearchBar
              entityType="venue"
              bulkDeleteAction={bulkDeleteVenues}
              bulkSetVerifiedAction={bulkSetVenuesVerified}
            />
            <div id="venues-table" className="mt-3 overflow-x-auto rounded-xl border border-black/[0.06] bg-white shadow-sm">
              <table className="w-full text-sm">
                <thead className={listTheadClass}>
                  <tr>
                    <th className="w-10 px-4 py-3">
                      <BioSelectAllCheckbox ids={data.map((v) => v.id)} />
                    </th>
                    <th className={listThClass}>Name</th>
                    <th className={listThClass}>Stadt</th>
                    <th className={listThClass}>Kapazität</th>
                    <th className={listThClass}>Termine</th>
                    <th className={listThClass}>Status</th>
                    <th className={listThClass}>Bio</th>
                    <th className={listThClass}>Bild</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-200">
                  {data.length ? (
                    data.map((venue) => (
                      <tr
                        key={venue.id}
                        className={listRowClass}
                      >
                        <td className="px-4 py-3">
                          <BioRowCheckbox id={venue.id} />
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-3">
                            <ListThumbnail src={venue.photo_url} alt={venue.name} />
                            <Link href={`/venues/${venue.id}`} className="font-medium text-neutral-900 hover:text-[#2D2A6E] hover:underline">{venue.name}</Link>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-neutral-600">{venue.address_city}</td>
                        <td className="px-4 py-3 text-neutral-600 tabular-nums">
                          {venue.capacity ?? "—"}
                        </td>
                        <td className="px-4 py-3 tabular-nums text-neutral-600">{venue.events?.[0]?.count ?? 0}</td>
                        <td className="px-4 py-3">
                          <VerifiedBadge verified={venue.is_verified} />
                        </td>
                        <td className="px-4 py-3">
                          <BioStatusBadge hasBio={!!venue.description_de} />
                        </td>
                        <td className="px-4 py-3">
                          <ImageStatusBadge hasImage={!!venue.photo_url} />
                        </td>
                        <td className="px-4 py-3 text-right">
                          <Link href={`/venues/${venue.id}`} className="text-sm font-medium text-neutral-700 hover:text-[#2D2A6E]">
                            Bearbeiten
                          </Link>
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={9} className="px-4 py-10 text-center text-neutral-400">
                        Keine Venues für diese Auswahl.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            <ListPagination basePath="/venues" params={params} total={total} />
          </div>
        </BioSelectionProvider>
      )}
    </div>
  );
}
