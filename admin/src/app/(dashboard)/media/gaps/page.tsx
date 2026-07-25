import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>;

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
}

async function loadEntityGaps(
  supabase: SupabaseServerClient,
  kind: EntityKind,
): Promise<GapRow[]> {
  const { data: rows } = await supabase
    .from(kind.table)
    .select(`id, ${kind.nameColumn}`)
    .is("photo_url", null);
  const candidates = (rows ?? []) as unknown as Array<Record<string, unknown>>;
  if (candidates.length === 0) return [];

  // Eine Zeile gilt nur dann als echte Lücke ("trotz automatischer
  // Recherche kein verlässliches Bild gefunden"), wenn AUCH kein
  // nicht-abgelehnter images-Kandidat existiert — sonst wartet sie nur
  // noch auf redaktionelle Freigabe in der Review-Queue (/media), ist also
  // kein "die Suche hat nichts gefunden"-Fall.
  const { data: pending } = await supabase
    .from("images")
    .select("origin_id")
    .eq("origin_type", kind.originType)
    .neq("license_status", "rejected")
    .in("origin_id", candidates.map((c) => c.id as string));
  const pendingIds = new Set((pending ?? []).map((p: { origin_id: string }) => p.origin_id));

  return candidates
    .filter((c) => !pendingIds.has(c.id as string))
    .map((c) => ({ id: c.id as string, name: (c[kind.nameColumn] as string) ?? "(ohne Namen)" }));
}

interface EventGapRow {
  id: string;
  title: string;
  start_datetime: string;
  website_url: string | null;
  ticket_url: string | null;
}

async function loadEventGaps(supabase: SupabaseServerClient): Promise<EventGapRow[]> {
  const { data } = await supabase
    .from("events")
    .select("id, title, start_datetime, website_url, ticket_url, image_urls")
    .in("status", ["scheduled", "sold_out", "postponed"])
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true });

  const rows = (data ?? []) as Array<EventGapRow & { image_urls: string[] | null }>;
  return rows
    .filter((e) => !e.image_urls || e.image_urls.length === 0)
    .map(({ id, title, start_datetime, website_url, ticket_url }) => ({
      id,
      title,
      start_datetime,
      website_url,
      ticket_url,
    }));
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

export default async function MediaGapsPage() {
  const supabase = await createClient();

  const [entityGaps, eventGaps] = await Promise.all([
    Promise.all(ENTITY_KINDS.map((kind) => loadEntityGaps(supabase, kind))),
    loadEventGaps(supabase),
  ]);

  const totalEntityGaps = entityGaps.reduce((sum, rows) => sum + rows.length, 0);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Bildlücken</h1>
          <p className="mt-1 max-w-2xl text-sm text-neutral-500">
            Datensätze ohne Foto/Titelbild, bei denen die automatische Bildersuche (eigene Website,
            Wikimedia-Fallback) bislang kein verlässliches, erreichbares Bild gefunden hat — nicht
            enthalten sind Kandidaten, die schon in der{" "}
            <Link href="/media" className="text-blue-600 hover:underline">
              Lizenz-Review-Queue
            </Link>{" "}
            auf Freigabe warten. Der automatische Anreicherungs-Lauf (alle 15 Minuten) greift diese
            Lücken von selbst wieder auf, sobald sich z. B. eine website_url ändert oder eine neue
            Wikimedia-Quelle verfügbar wird.
          </p>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-5">
        <div className="rounded-lg border border-neutral-200 bg-white p-4">
          <p className="text-2xl font-semibold tabular-nums">{totalEntityGaps}</p>
          <p className="text-xs text-neutral-500">Entitäten ohne Bild</p>
        </div>
        <div className="rounded-lg border border-neutral-200 bg-white p-4">
          <p className="text-2xl font-semibold tabular-nums">{eventGaps.length}</p>
          <p className="text-xs text-neutral-500">Events ohne Titelbild</p>
        </div>
      </div>

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
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {eventGaps.map((row) => (
                  <tr key={row.id} className="hover:bg-neutral-50">
                    <td className="px-4 py-2.5 text-neutral-900">{row.title}</td>
                    <td className="px-4 py-2.5 text-neutral-600 tabular-nums">{formatDate(row.start_datetime)}</td>
                    <td className="px-4 py-2.5 text-neutral-500">
                      {!row.website_url && !row.ticket_url
                        ? "Keine Website/Ticket-URL hinterlegt"
                        : "Website/Ticket-Seite ohne nutzbares og:image (oder per robots.txt gesperrt)"}
                    </td>
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
