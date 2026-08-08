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
import { bulkDeletePersons, bulkSetPersonsVerified } from "./actions";

export const dynamic = "force-dynamic";

interface PersonRow {
  id: string;
  full_name: string;
  roles: string[];
  is_verified: boolean;
  biography_de: string | null;
  photo_url: string | null;
}

const ROLE_LABEL: Record<string, string> = {
  komponist: "Komponist:in",
  dirigent: "Dirigent:in",
  solist: "Solist:in",
  chorleiter: "Chorleiter:in",
  moderator: "Moderator:in",
};

export default async function PersonsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("persons")
    .select("id, full_name, roles, is_verified, biography_de, photo_url")
    .order("full_name")
    .returns<PersonRow[]>();

  const missingBioIds = (data ?? []).filter((p) => !p.biography_de).map((p) => p.id);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Personen & Ensembles</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Komponist:innen, Dirigent:innen, Solist:innen.{" "}
            <Link href="/ensembles" className="underline hover:text-neutral-700">
              Chöre & Orchester verwalten →
            </Link>
          </p>
        </div>
        <Link
          href="/persons/new"
          className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700"
        >
          Neu anlegen
        </Link>
      </div>

      {error && (
        <p className="mt-6 text-sm text-amber-700">Konnte Personen nicht laden: {error.message}</p>
      )}

      {!error && (
        <BioSelectionProvider>
          <div className="mt-6">
            <div className="flex items-center justify-between">
              <TableSearchFilter containerId="persons-table" placeholder="Name durchsuchen…" />
              <BioSelectMissingButton ids={missingBioIds} />
            </div>
            <BioResearchBar
              entityType="person"
              bulkDeleteAction={bulkDeletePersons}
              bulkSetVerifiedAction={bulkSetPersonsVerified}
            />
            <div id="persons-table" className="overflow-hidden rounded-lg border border-neutral-200 bg-white">
              <table className="w-full text-sm">
                <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                  <tr>
                    <th className="w-10 px-4 py-3">
                      <BioSelectAllCheckbox ids={(data ?? []).map((p) => p.id)} />
                    </th>
                    <th className="px-4 py-3 font-medium">Name</th>
                    <th className="px-4 py-3 font-medium">Rollen</th>
                    <th className="px-4 py-3 font-medium">Status</th>
                    <th className="px-4 py-3 font-medium">Bio</th>
                    <th className="px-4 py-3 font-medium">Bild</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-100">
                  {data?.length ? (
                    data.map((person) => (
                      <tr
                        key={person.id}
                        data-search={person.full_name.toLowerCase()}
                        className="hover:bg-neutral-50"
                      >
                        <td className="px-4 py-3">
                          <BioRowCheckbox id={person.id} />
                        </td>
                        <td className="px-4 py-3 font-medium text-neutral-900">{person.full_name}</td>
                        <td className="px-4 py-3 text-neutral-600">
                          {person.roles.map((r) => ROLE_LABEL[r] ?? r).join(", ") || "—"}
                        </td>
                        <td className="px-4 py-3">
                          <span
                            className={`rounded-full px-2.5 py-1 text-xs font-medium ${
                              person.is_verified
                                ? "bg-emerald-50 text-emerald-700"
                                : "bg-neutral-100 text-neutral-600"
                            }`}
                          >
                            {person.is_verified ? "Geprüft" : "Ungeprüft"}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <BioStatusBadge hasBio={!!person.biography_de} />
                        </td>
                        <td className="px-4 py-3">
                          <ImageStatusBadge hasImage={!!person.photo_url} />
                        </td>
                        <td className="px-4 py-3 text-right">
                          <Link
                            href={`/persons/${person.id}`}
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
                        Noch keine Personen angelegt.
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
