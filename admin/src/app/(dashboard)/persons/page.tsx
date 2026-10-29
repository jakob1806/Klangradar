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
import { bulkDeletePersons, bulkSetPersonsVerified } from "./actions";

export const dynamic = "force-dynamic";

interface PersonRow {
  id: string;
  full_name: string;
  roles: string[];
  is_verified: boolean;
  biography_de: string | null;
  photo_url: string | null;
  ai_biography_status: "pending" | "processing" | "generated" | "not_known" | "error";
  last_image_search_note: string | null;
  event_participants: { count: number }[];
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

const FILTERS = [
  { key: "all", label: "Alle" },
  { key: "no_photo", label: "Ohne Foto" },
  { key: "no_bio", label: "Ohne Biografie" },
  { key: "unverified", label: "Ungeprüft" },
  { key: "komponist", label: "Komponist:innen" },
  { key: "dirigent", label: "Dirigent:innen" },
];
const SORTS = [
  { key: "name", label: "Name A–Z" },
  { key: "updated", label: "Zuletzt geändert" },
  { key: "created", label: "Neueste zuerst" },
];

// Erweiterung (Claude Code, 29.10.2026): Suche, Filter, Sortierung und
// Seiten serverseitig (components/entity-list.tsx). Vorher wurden alle
// Personen seitenweise komplett geladen und nur im Browser gefiltert.
export default async function PersonsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = readListParams(await searchParams, FILTERS, SORTS);
  const supabase = await createClient();
  let query = supabase
    .from("persons")
    .select("id, full_name, roles, is_verified, biography_de, photo_url, ai_biography_status, last_image_search_note, event_participants(count)", { count: "exact" });
  if (params.q) query = query.ilike("full_name", ilikePattern(params.q));
  if (params.filter === "no_photo") query = query.is("photo_url", null);
  if (params.filter === "no_bio") query = query.is("biography_de", null);
  if (params.filter === "unverified") query = query.eq("is_verified", false);
  if (params.filter === "komponist" || params.filter === "dirigent") query = query.contains("roles", [params.filter]);
  query =
    params.sort === "updated"
      ? query.order("updated_at", { ascending: false, nullsFirst: false })
      : params.sort === "created"
        ? query.order("created_at", { ascending: false })
        : query.order("full_name");
  const [from, to] = listRange(params);
  const { data: rows, error: queryError, count } = await query.range(from, to).returns<PersonRow[]>();
  const data = rows ?? [];
  const error = queryError?.message ?? null;
  const total = count ?? 0;

  const missingBioIds = data.filter((p) => !p.biography_de).map((p) => p.id);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Personen</h1>
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
            className="rounded-lg bg-[#2D2A6E] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#38358a]"
          >
            Neu anlegen
          </Link>
        </div>
      </div>

      {error && (
        <p className="mt-6 text-sm text-amber-700">Konnte Personen nicht laden: {error}</p>
      )}

      {!error && (
        <BioSelectionProvider>
          <div className="mt-6">
            <ListToolbar basePath="/persons" params={params} filters={FILTERS} sorts={SORTS} total={total} searchPlaceholder="Name suchen …">
              <BioSelectMissingButton ids={missingBioIds} />
            </ListToolbar>
            <BioResearchBar
              entityType="person"
              bulkDeleteAction={bulkDeletePersons}
              bulkSetVerifiedAction={bulkSetPersonsVerified}
            />
            <div id="persons-table" className="mt-3 overflow-x-auto rounded-xl border border-black/[0.06] bg-white shadow-sm">
              <table className="w-full text-sm">
                <thead className={listTheadClass}>
                  <tr>
                    <th className="w-10 px-4 py-3">
                      <BioSelectAllCheckbox ids={data.map((p) => p.id)} />
                    </th>
                    <th className={listThClass}>Name</th>
                    <th className={listThClass}>Rollen</th>
                    <th className={listThClass}>Termine</th>
                    <th className={listThClass}>Status</th>
                    <th className={listThClass}>Bio</th>
                    <th className={listThClass}>Bild</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-200">
                  {data.length ? (
                    data.map((person) => (
                      <tr
                        key={person.id}
                        className={listRowClass}
                      >
                        <td className="px-4 py-3">
                          <BioRowCheckbox id={person.id} />
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-3">
                            <ListThumbnail src={person.photo_url} alt={person.full_name} rounded />
                            <Link href={`/persons/${person.id}`} className="font-medium text-neutral-900 hover:text-[#2D2A6E] hover:underline">
                              {person.full_name}
                            </Link>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-neutral-600">
                          {person.roles.map((r) => ROLE_LABEL[r] ?? r).join(", ") || "—"}
                        </td>
                        <td className="px-4 py-3 tabular-nums text-neutral-600">{person.event_participants?.[0]?.count ?? 0}</td>
                        <td className="px-4 py-3">
                          <VerifiedBadge verified={person.is_verified} />
                        </td>
                        <td className="px-4 py-3">
                          <BioStatusBadge hasBio={!!person.biography_de} aiStatus={person.ai_biography_status} />
                        </td>
                        <td className="px-4 py-3">
                          <ImageStatusBadge hasImage={!!person.photo_url} searchNote={person.last_image_search_note} />
                        </td>
                        <td className="px-4 py-3 text-right">
                          <Link
                            href={`/persons/${person.id}`}
                            className="text-sm font-medium text-neutral-700 hover:text-[#2D2A6E]"
                          >
                            Bearbeiten
                          </Link>
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={8} className="px-4 py-10 text-center text-neutral-400">
                        {params.q || params.filter !== "all" ? "Keine Personen für diese Auswahl." : "Noch keine Personen angelegt."}
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            <ListPagination basePath="/persons" params={params} total={total} />
          </div>
        </BioSelectionProvider>
      )}
    </div>
  );
}
