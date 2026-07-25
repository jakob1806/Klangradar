import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>;

type GapReason = "no_source" | "blocked" | "not_found" | "review_pending";

const REASON_LABEL: Record<GapReason, string> = {
  no_source: "Keine Quelle vorhanden",
  blocked: "Quelle blockiert",
  not_found: "Bild nicht eindeutig genug",
  review_pending: "Lizenzprüfung erforderlich",
};

const REASON_STYLE: Record<GapReason, string> = {
  no_source: "bg-neutral-100 text-neutral-600",
  blocked: "bg-red-50 text-red-700",
  not_found: "bg-amber-50 text-amber-700",
  review_pending: "bg-blue-50 text-blue-700",
};

/** Kategorisiert die in last_image_search_note gespeicherte Freitext-
 * Begründung (siehe enrich-entity-images/index.ts, setNote()) in eine der
 * vier vom Nutzer verlangten Gruppen — bewusst anhand des tatsächlich
 * gespeicherten Laufergebnisses, nicht nachträglich geraten. */
function categorize(note: string | null): GapReason {
  if (!note) return "not_found";
  if (note.includes("wartet auf")) return "review_pending";
  if (note.includes("Keine Website") && !note.includes("Websuche")) return "no_source";
  if (note.includes("robots.txt")) return "blocked";
  return "not_found";
}

interface EntityKind {
  table: string;
  originType: "venue" | "person" | "ensemble" | "festival";
  nameColumn: string;
  label: string;
  editPathPrefix: string;
}

const ENTITY_KINDS: EntityKind[] = [
  { table: "venues", originType: "venue", nameColumn: "name", label: "Venues", editPathPrefix: "/venues" },
  { table: "persons", originType: "person", nameColumn: "full_name", label: "Personen", editPathPrefix: "/persons" },
  { table: "ensembles", originType: "ensemble", nameColumn: "name", label: "Ensembles", editPathPrefix: "/ensembles" },
  { table: "festivals", originType: "festival", nameColumn: "name", label: "Festivals", editPathPrefix: "/festivals" },
];

interface GapRow {
  id: string;
  name: string;
  reason: GapReason;
  note: string | null;
}

async function loadEntityGaps(
  supabase: SupabaseServerClient,
  kind: EntityKind,
): Promise<GapRow[]> {
  const { data: rows } = await supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}, last_image_search_note`)
    .is("photo_url", null);
  const candidates = (rows ?? []) as unknown as Array<Record<string, unknown>>;
  if (candidates.length === 0) return [];

  // Ein Kandidat, der bereits (nicht abgelehnt) in der Review-Queue
  // wartet, gehört zur Kategorie "Lizenzprüfung erforderlich" — die
  // last_image_search_note allein reicht dafür nicht (die Note wird nur
  // beim Anreicherungslauf selbst gesetzt, nicht bei jedem Seitenaufruf
  // neu abgeglichen), daher ein direkter Check gegen die images-Tabelle.
  const { data: pending } = await supabase
    .from("images")
    .select("origin_id")
    .eq("origin_type", kind.originType)
    .neq("license_status", "rejected")
    .in("origin_id", candidates.map((c) => c.id as string));
  const pendingIds = new Set((pending ?? []).map((p: { origin_id: string }) => p.origin_id));

  return candidates.map((c) => {
    const id = c.id as string;
    const note = (c.last_image_search_note as string | null) ?? null;
    return {
      id,
      name: (c[kind.nameColumn] as string) ?? "(ohne Namen)",
      reason: pendingIds.has(id) ? "review_pending" : categorize(note),
      note,
    };
  });
}

interface EventGapRow {
  id: string;
  title: string;
  start_datetime: string;
  reason: GapReason;
  note: string | null;
}

async function loadEventGaps(supabase: SupabaseServerClient): Promise<EventGapRow[]> {
  const { data } = await supabase
    .from("events")
    .select("id, title, start_datetime, image_urls, last_image_search_note")
    .in("status", ["scheduled", "sold_out", "postponed"])
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true });

  const rows = (data ?? []) as Array<
    { id: string; title: string; start_datetime: string; image_urls: string[] | null; last_image_search_note: string | null }
  >;
  return rows
    .filter((e) => !e.image_urls || e.image_urls.length === 0)
    .map(({ id, title, start_datetime, last_image_search_note }) => ({
      id,
      title,
      start_datetime,
      reason: categorize(last_image_search_note),
      note: last_image_search_note,
    }));
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

function ReasonBadge({ reason }: { reason: GapReason }) {
  return (
    <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${REASON_STYLE[reason]}`}>
      {REASON_LABEL[reason]}
    </span>
  );
}

export default async function MediaGapsPage() {
  const supabase = await createClient();

  const [entityGaps, eventGaps] = await Promise.all([
    Promise.all(ENTITY_KINDS.map((kind) => loadEntityGaps(supabase, kind))),
    loadEventGaps(supabase),
  ]);

  const allGaps = [...entityGaps.flat().map((g) => g.reason), ...eventGaps.map((g) => g.reason)];
  const reasonCounts: Record<GapReason, number> = {
    no_source: allGaps.filter((r) => r === "no_source").length,
    blocked: allGaps.filter((r) => r === "blocked").length,
    not_found: allGaps.filter((r) => r === "not_found").length,
    review_pending: allGaps.filter((r) => r === "review_pending").length,
  };
  const totalEntityGaps = entityGaps.reduce((sum, rows) => sum + rows.length, 0);

  return (
    <div className="p-8">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Bildlücken</h1>
        <p className="mt-1 max-w-2xl text-sm text-neutral-500">
          Alle Datensätze ohne Foto/Titelbild, aufgeschlüsselt nach dem tatsächlichen Grund aus dem
          letzten automatischen Anreicherungslauf (alle 15 Minuten). &bdquo;Lizenzprüfung
          erforderlich&rdquo; wartet in der{" "}
          <Link href="/media" className="text-blue-600 hover:underline">
            Review-Queue
          </Link>{" "}
          auf eine redaktionelle Entscheidung — alle anderen Gründe werden beim nächsten Lauf
          automatisch erneut versucht.
        </p>
      </div>

      <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        {(Object.keys(REASON_LABEL) as GapReason[]).map((reason) => (
          <div key={reason} className="rounded-lg border border-neutral-200 bg-white p-4">
            <p className="text-2xl font-semibold tabular-nums">{reasonCounts[reason]}</p>
            <p className="text-xs text-neutral-500">{REASON_LABEL[reason]}</p>
          </div>
        ))}
      </div>
      <p className="mt-3 text-xs text-neutral-400">
        {totalEntityGaps} Entitäten ohne Bild · {eventGaps.length} Events ohne Titelbild
      </p>

      {ENTITY_KINDS.map((kind, i) => (
        <section key={kind.table} className="mt-8">
          <h2 className="text-sm font-semibold tracking-tight text-neutral-900">
            {kind.label} <span className="font-normal text-neutral-400">({entityGaps[i].length})</span>
          </h2>
          {entityGaps[i].length === 0 ? (
            <p className="mt-2 text-sm text-neutral-400">Keine Lücken.</p>
          ) : (
            <div className="mt-2 overflow-hidden rounded-lg border border-neutral-200 bg-white">
              <table className="w-full text-sm">
                <tbody className="divide-y divide-neutral-100">
                  {entityGaps[i].map((row) => (
                    <tr key={row.id} className="hover:bg-neutral-50">
                      <td className="px-4 py-2.5 text-neutral-900">{row.name}</td>
                      <td className="px-4 py-2.5">
                        <ReasonBadge reason={row.reason} />
                      </td>
                      <td className="px-4 py-2.5 text-neutral-500">{row.note ?? "—"}</td>
                      <td className="px-4 py-2.5 text-right">
                        <Link
                          href={`${kind.editPathPrefix}/${row.id}`}
                          className="text-xs font-medium text-neutral-700 hover:text-neutral-900"
                        >
                          Bearbeiten
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      ))}

      <section className="mt-8">
        <h2 className="text-sm font-semibold tracking-tight text-neutral-900">
          Events <span className="font-normal text-neutral-400">({eventGaps.length})</span>
        </h2>
        {eventGaps.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-400">Keine Lücken.</p>
        ) : (
          <div className="mt-2 overflow-hidden rounded-lg border border-neutral-200 bg-white">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-3 font-medium">Titel</th>
                  <th className="px-4 py-3 font-medium">Beginn</th>
                  <th className="px-4 py-3 font-medium">Grund</th>
                  <th className="px-4 py-3 font-medium">Details</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {eventGaps.map((row) => (
                  <tr key={row.id} className="hover:bg-neutral-50">
                    <td className="px-4 py-2.5 text-neutral-900">{row.title}</td>
                    <td className="px-4 py-2.5 text-neutral-600 tabular-nums">{formatDate(row.start_datetime)}</td>
                    <td className="px-4 py-2.5">
                      <ReasonBadge reason={row.reason} />
                    </td>
                    <td className="px-4 py-2.5 text-neutral-500">{row.note ?? "—"}</td>
                    <td className="px-4 py-2.5 text-right">
                      <Link
                        href={`/events/${row.id}`}
                        className="text-xs font-medium text-neutral-700 hover:text-neutral-900"
                      >
                        Bearbeiten
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
