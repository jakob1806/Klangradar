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
import { TableSearchFilter } from "@/components/table-search-filter";
import { bulkDeleteEnsembles, bulkSetEnsemblesVerified } from "./actions";

export const dynamic = "force-dynamic";

interface EnsembleRow {
  id: string;
  name: string;
  type: string;
  is_verified: boolean;
  description_de: string | null;
  photo_url: string | null;
}

const TYPE_LABEL: Record<string, string> = {
  chor: "Chor",
  orchester: "Orchester",
  kammerensemble: "Kammerensemble",
  big_band: "Big Band",
  sonstiges: "Sonstiges",
};

export default async function EnsemblesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ensembles")
    .select("id, name, type, is_verified, description_de, photo_url")
    .order("name")
    .returns<EnsembleRow[]>();

  const missingBioIds = (data ?? []).filter((e) => !e.description_de).map((e) => e.id);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Ensembles</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Chöre, Orchester und Kammerensembles.{" "}
            <Link href="/persons" className="underline hover:text-neutral-700">
              ← Personen verwalten
            </Link>
          </p>
        </div>
        <Link
          href="/ensembles/new"
          className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700"
        >
          Neu anlegen
        </Link>
      </div>

      {error && (
        <p className="mt-6 text-sm text-amber-700">Konnte Ensembles nicht laden: {error.message}</p>
      )}

      {!error && (
        <BioSelectionProvider>
          <div className="mt-6">
            <div className="flex items-center justify-between">
              <TableSearchFilter containerId="ensembles-table" placeholder="Name durchsuchen…" />
              <BioSelectMissingButton ids={missingBioIds} />
            </div>
            <BioResearchBar
              entityType="ensemble"
              bulkDeleteAction={bulkDeleteEnsembles}
              bulkSetVerifiedAction={bulkSetEnsemblesVerified}
            />
            <div id="ensembles-table" className="overflow-hidden rounded-lg border border-neutral-200 bg-white">
              <table className="w-full text-sm">
                <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                  <tr>
                    <th className="w-10 px-4 py-3">
                      <BioSelectAllCheckbox ids={(data ?? []).map((e) => e.id)} />
                    </th>
                    <th className="px-4 py-3 font-medium">Name</th>
                    <th className="px-4 py-3 font-medium">Typ</th>
                    <th className="px-4 py-3 font-medium">Status</th>
                    <th className="px-4 py-3 font-medium">Bio</th>
                    <th className="px-4 py-3 font-medium">Bild</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-100">
                  {data?.length ? (
                    data.map((ensemble) => (
                      <tr
                        key={ensemble.id}
                        data-search={ensemble.name.toLowerCase()}
                        className="hover:bg-neutral-50"
                      >
                        <td className="px-4 py-3">
                          <BioRowCheckbox id={ensemble.id} />
                        </td>
                        <td className="px-4 py-3 font-medium text-neutral-900">{ensemble.name}</td>
                        <td className="px-4 py-3 text-neutral-600">
                          {TYPE_LABEL[ensemble.type] ?? ensemble.type}
                        </td>
                        <td className="px-4 py-3">
                          <span
                            className={`rounded-full px-2.5 py-1 text-xs font-medium ${
                              ensemble.is_verified
                                ? "bg-emerald-50 text-emerald-700"
                                : "bg-neutral-100 text-neutral-600"
                            }`}
                          >
                            {ensemble.is_verified ? "Geprüft" : "Ungeprüft"}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <BioStatusBadge hasBio={!!ensemble.description_de} />
                        </td>
                        <td className="px-4 py-3">
                          <ImageStatusBadge hasImage={!!ensemble.photo_url} />
                        </td>
                        <td className="px-4 py-3 text-right">
                          <Link
                            href={`/ensembles/${ensemble.id}`}
                            className="text-sm font-medium text-neutral-700 hover:text-neutral-900"
                          >
                            Bearbeiten
                          </Link>
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={7} className="px-4 py-10 text-center text-neutral-400">
                        Noch keine Ensembles angelegt.
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
