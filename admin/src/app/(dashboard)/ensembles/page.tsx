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
import { bulkDeleteEnsembles, bulkSetEnsemblesVerified } from "./actions";

export const dynamic = "force-dynamic";

interface EnsembleRow {
  id: string;
  name: string;
  type: string;
  is_verified: boolean;
  description_de: string | null;
  photo_url: string | null;
  parent_ensemble_id: string | null;
  family_role: string | null;
  is_family_root: boolean;
  is_resolution_placeholder: boolean;
  event_participants: { count: number }[];
}

const TYPE_LABEL: Record<string, string> = {
  chor: "Chor",
  orchester: "Orchester",
  kammerensemble: "Kammerensemble",
  big_band: "Big Band",
  sonstiges: "Sonstiges",
};

const FILTERS = [
  { key: "active", label: "Aktive" },
  { key: "no_photo", label: "Ohne Foto" },
  { key: "no_bio", label: "Ohne Beschreibung" },
  { key: "unverified", label: "Ungeprüft" },
  { key: "sub", label: "Unterensembles" },
  { key: "technical", label: "Technische Sammelbegriffe" },
];
const SORTS = [
  { key: "name", label: "Name A–Z" },
  { key: "updated", label: "Zuletzt geändert" },
  { key: "created", label: "Neueste zuerst" },
];

// Erweiterung (Claude Code, 29.10.2026): Suche, Filter, Sortierung und
// Seiten serverseitig (components/entity-list.tsx). "?ansicht=technisch"
// (alte Links) entspricht dem Filter "Technische Sammelbegriffe".
export default async function EnsemblesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const raw = await searchParams;
  if (raw.ansicht === "technisch" && !raw.filter) raw.filter = "technical";
  const params = readListParams(raw, FILTERS, SORTS);
  const supabase = await createClient();
  let query = supabase
    .from("ensembles")
    .select("id, name, type, is_verified, description_de, photo_url, parent_ensemble_id, family_role, is_family_root, is_resolution_placeholder, event_participants(count)", { count: "exact" });
  if (params.q) query = query.ilike("name", ilikePattern(params.q));
  if (params.filter === "technical") query = query.eq("is_resolution_placeholder", true);
  else query = query.eq("is_resolution_placeholder", false).eq("is_family_root", false);
  if (params.filter === "no_photo") query = query.is("photo_url", null);
  if (params.filter === "no_bio") query = query.is("description_de", null);
  if (params.filter === "unverified") query = query.eq("is_verified", false);
  if (params.filter === "sub") query = query.not("parent_ensemble_id", "is", null);
  query =
    params.sort === "updated"
      ? query.order("updated_at", { ascending: false, nullsFirst: false })
      : params.sort === "created"
        ? query.order("created_at", { ascending: false })
        : query.order("name");
  const [from, to] = listRange(params);
  const { data: rows, error, count } = await query.range(from, to).returns<EnsembleRow[]>();
  const data = rows ?? [];
  const total = count ?? 0;

  const missingBioIds = data.filter((e) => !e.description_de).map((e) => e.id);

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
          href="/ensemble-families"
          className="border border-neutral-300 bg-white px-4 py-2 text-sm font-medium transition-colors hover:bg-neutral-50"
        >
          Familien verwalten
        </Link>
        <Link href="/ensembles/new" className="rounded-lg bg-[#2D2A6E] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#38358a]">Neu anlegen</Link>
      </div>

      {error && (
        <p className="mt-6 text-sm text-amber-700">Konnte Ensembles nicht laden: {error.message}</p>
      )}

      {!error && (
        <BioSelectionProvider>
          <div className="mt-6">
            <ListToolbar basePath="/ensembles" params={params} filters={FILTERS} sorts={SORTS} total={total} searchPlaceholder="Name suchen …">
              <BioSelectMissingButton ids={missingBioIds} />
            </ListToolbar>
            <BioResearchBar
              entityType="ensemble"
              bulkDeleteAction={bulkDeleteEnsembles}
              bulkSetVerifiedAction={bulkSetEnsemblesVerified}
            />
            <div id="ensembles-table" className="mt-3 overflow-x-auto rounded-xl border border-black/[0.06] bg-white shadow-sm">
              <table className="w-full text-sm">
                <thead className={listTheadClass}>
                  <tr>
                    <th className="w-10 px-4 py-3">
                      <BioSelectAllCheckbox ids={data.map((e) => e.id)} />
                    </th>
                    <th className={listThClass}>Name</th>
                    <th className={listThClass}>Typ</th>
                    <th className={listThClass}>Termine</th>
                    <th className={listThClass}>Status</th>
                    <th className={listThClass}>Bio</th>
                    <th className={listThClass}>Bild</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-200">
                  {data.length ? (
                    data.map((ensemble) => (
                      <tr
                        key={ensemble.id}
                        className={listRowClass}
                      >
                        <td className="px-4 py-3">
                          <BioRowCheckbox id={ensemble.id} />
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-3">
                            <ListThumbnail src={ensemble.photo_url} alt={ensemble.name} />
                            <div><Link href={`/ensembles/${ensemble.id}`} className="font-medium text-neutral-900 hover:text-[#2D2A6E] hover:underline">{ensemble.name}</Link><div className="mt-1 flex flex-wrap gap-1">{ensemble.is_family_root && <span className="type-label border border-violet-200 bg-violet-50 px-1.5 py-0.5 !text-violet-700">Dachorganisation</span>}{ensemble.parent_ensemble_id && <span className="type-label border border-blue-200 bg-blue-50 px-1.5 py-0.5 !text-blue-700">Unterensemble</span>}{ensemble.is_resolution_placeholder && <span className="type-label border border-amber-200 bg-amber-50 px-1.5 py-0.5 !text-amber-700">Sammelbegriff</span>}</div></div>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-neutral-600">
                          {TYPE_LABEL[ensemble.type] ?? ensemble.type}
                        </td>
                        <td className="px-4 py-3 tabular-nums text-neutral-600">{ensemble.event_participants?.[0]?.count ?? 0}</td>
                        <td className="px-4 py-3">
                          <VerifiedBadge verified={ensemble.is_verified} />
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
                        Keine Ensembles für diese Auswahl.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            <ListPagination basePath="/ensembles" params={params} total={total} />
          </div>
        </BioSelectionProvider>
      )}
    </div>
  );
}
