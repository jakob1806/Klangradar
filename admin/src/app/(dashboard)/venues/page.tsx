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
import { TableSearchFilter } from "@/components/table-search-filter";
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
}

export default async function VenuesPage() {
  const supabase = await createClient();
  const cityFilter = await getActiveCityFilter();
  let query = supabase
    .from("venues")
    .select("id, name, address_city, capacity, is_verified, description_de, photo_url")
    .order("name");
  if (cityFilter.cityId) query = query.eq("city_id", cityFilter.cityId);
  const { data, error } = await query.returns<VenueRow[]>();

  const missingBioIds = (data ?? []).filter((v) => !v.description_de).map((v) => v.id);

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
          className="rounded-lg bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
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
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <TableSearchFilter containerId="venues-table" placeholder="Name durchsuchen…" />
              </div>
              <BioSelectMissingButton ids={missingBioIds} />
            </div>
            <BioResearchBar
              entityType="venue"
              bulkDeleteAction={bulkDeleteVenues}
              bulkSetVerifiedAction={bulkSetVenuesVerified}
            />
            <div id="venues-table" className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
              <table className="w-full text-sm">
                <thead className="border-b border-black/[0.06] text-left">
                  <tr>
                    <th className="w-10 px-4 py-3">
                      <BioSelectAllCheckbox ids={(data ?? []).map((v) => v.id)} />
                    </th>
                    <th className="type-label px-4 py-3">Name</th>
                    <th className="type-label px-4 py-3">Stadt</th>
                    <th className="type-label px-4 py-3">Kapazität</th>
                    <th className="type-label px-4 py-3">Status</th>
                    <th className="type-label px-4 py-3">Bio</th>
                    <th className="type-label px-4 py-3">Bild</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-200">
                  {data?.length ? (
                    data.map((venue) => (
                      <tr
                        key={venue.id}
                        data-search={venue.name.toLowerCase()}
                        className="hover:bg-neutral-50"
                      >
                        <td className="px-4 py-3">
                          <BioRowCheckbox id={venue.id} />
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-3">
                            <ListThumbnail src={venue.photo_url} alt={venue.name} />
                            <span className="font-medium text-neutral-900">{venue.name}</span>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-neutral-600">{venue.address_city}</td>
                        <td className="px-4 py-3 text-neutral-600 tabular-nums">
                          {venue.capacity ?? "—"}
                        </td>
                        <td className="px-4 py-3">
                          <span
                            className={`type-label border px-2 py-1 ${
                              venue.is_verified
                                ? "border-emerald-700 !text-emerald-700"
                                : "border-neutral-300 !text-neutral-500"
                            }`}
                          >
                            {venue.is_verified ? "Geprüft" : "Ungeprüft"}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <BioStatusBadge hasBio={!!venue.description_de} />
                        </td>
                        <td className="px-4 py-3">
                          <ImageStatusBadge hasImage={!!venue.photo_url} />
                        </td>
                        <td className="px-4 py-3 text-right">
                          <Link href={`/venues/${venue.id}`} className="text-sm font-medium text-neutral-700 hover:text-[#0071e3]">
                            Bearbeiten
                          </Link>
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={8} className="px-4 py-10 text-center text-neutral-400">
                        Noch keine Venues angelegt.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </BioSelectionProvider>
      )}
    </div>
  );
}
