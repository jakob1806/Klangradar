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

// Nur Anzeige-Beschriftung, keine Einschränkung — persons.roles ist text[]
// (siehe 20261013000014_persons_roles_free_text.sql), unbekannte Werte
// werden weiter unten unverändert als Rohtext angezeigt (ROLE_LABEL[r] ?? r).
const ROLE_LABEL: Record<string, string> = {
  komponist: "Komponist:in",
  dirigent: "Dirigent:in",
  solist: "Solist:in",
  chorleiter: "Chorleiter:in",
  moderator: "Moderator:in",
  regisseur: "Regisseur:in",
  schauspieler: "Schauspieler:in",
  choreograf: "Choreograf:in",
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
        <div className="flex items-center gap-2">
          <Link
            href="/qualitaetspruefung?type=person"
            className="rounded-lg border border-violet-200 bg-violet-50 px-4 py-2 text-sm font-medium text-violet-900 transition-colors hover:bg-violet-100"
          >
            Qualitätsprüfung
          </Link>
          <Link
            href="/persons/new"
            className="rounded-lg bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
          >
            Neu anlegen
          </Link>
        </div>
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
            <div id="persons-table" className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
              <table className="w-full text-sm">
                <thead className="border-b border-black/[0.06] text-left">
                  <tr>
                    <th className="w-10 px-4 py-3">
                      <BioSelectAllCheckbox ids={(data ?? []).map((p) => p.id)} />
                    </th>
                    <th className="type-label px-4 py-3">Name</th>
                    <th className="type-label px-4 py-3">Rollen</th>
                    <th className="type-label px-4 py-3">Status</th>
                    <th className="type-label px-4 py-3">Bio</th>
                    <th className="type-label px-4 py-3">Bild</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-200">
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
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-3">
                            <ListThumbnail src={person.photo_url} alt={person.full_name} rounded />
                            <span className="font-medium text-neutral-900">{person.full_name}</span>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-neutral-600">
                          {person.roles.map((r) => ROLE_LABEL[r] ?? r).join(", ") || "—"}
                        </td>
                        <td className="px-4 py-3">
                          <span
                            className={`type-label border px-2 py-1 ${
                              person.is_verified
                                ? "border-emerald-700 !text-emerald-700"
                                : "border-neutral-300 !text-neutral-500"
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
                            className="text-sm font-medium text-neutral-700 hover:text-[#0071e3]"
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
