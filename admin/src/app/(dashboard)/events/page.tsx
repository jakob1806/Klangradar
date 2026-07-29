import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import {
  BulkActionBar,
  BulkSelectionProvider,
  PublishRowButton,
  RowCheckbox,
  SelectAllCheckbox,
} from "./bulk-select";

// Event-Daten ändern sich häufig (Preise, Restkarten) — nie statisch cachen.
export const dynamic = "force-dynamic";

const PAGE_SIZE = 50;

interface EventRow {
  id: string;
  slug: string;
  title: string;
  start_datetime: string;
  status: string;
  venues: { name: string } | null;
  sources: { name: string } | null;
}

const STATUS_LABEL: Record<string, string> = {
  scheduled: "Geplant",
  sold_out: "Ausverkauft",
  cancelled: "Abgesagt",
  postponed: "Verschoben",
  draft: "Entwurf",
};

// "all" ist kein echter events.status-Wert, sondern der Tab ohne Filter.
const STATUS_TABS = [
  { value: "draft", label: "Entwürfe" },
  { value: "scheduled", label: "Geplant" },
  { value: "all", label: "Alle" },
] as const;

export default async function EventsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; page?: string; q?: string }>;
}) {
  const params = await searchParams;
  // Entwürfe zuerst als Default: das ist review-pflichtiger Content aus der
  // Ingestion-Pipeline (236 Stand heute Nacht) — der dringendste Fall beim
  // Öffnen dieser Seite, nicht "alles chronologisch", das ihn bei .limit(50)
  // komplett aus der sichtbaren Liste verdrängt hätte.
  const status = params.status ?? "draft";
  const q = (params.q ?? "").trim();
  const page = Math.max(1, parseInt(params.page ?? "1", 10) || 1);
  const from = (page - 1) * PAGE_SIZE;
  const to = from + PAGE_SIZE - 1;

  const supabase = await createClient();

  // Server-seitig statt Client-Filter: die Liste ist paginiert (50/Seite),
  // ein reiner Client-Filter würde nur innerhalb der gerade geladenen Seite
  // suchen, nicht über alle Events hinweg.
  let query = supabase
    .from("events")
    .select("id, slug, title, start_datetime, status, venues(name), sources(name)", { count: "exact" });
  if (status !== "all") {
    query = query.eq("status", status);
  }
  if (q) {
    query = query.ilike("title", `%${q}%`);
  }
  const { data, error, count } = await query
    .order("start_datetime", { ascending: true })
    .range(from, to)
    .returns<EventRow[]>();

  const { data: statusCounts } = await supabase.from("events").select("status");
  const countByStatus = new Map<string, number>();
  for (const row of statusCounts ?? []) {
    countByStatus.set(row.status, (countByStatus.get(row.status) ?? 0) + 1);
  }
  const totalCount = statusCounts?.length ?? 0;

  const totalPages = count ? Math.ceil(count / PAGE_SIZE) : 1;

  return (
    <div className="p-8">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Veranstaltungen</h1>
          <p className="text-sm text-neutral-500">Kommende Events, redaktionell prüfbar.</p>
        </div>
        <div className="flex items-center gap-3">
          <Link
            href="/events/from-url"
            className="rounded-md border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
          >
            Von URL hinzufügen
          </Link>
          <Link
            href="/events/new"
            className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700"
          >
            Neu anlegen
          </Link>
        </div>
      </div>

      <div className="mb-4 flex items-center gap-1 border-b border-neutral-200">
        {STATUS_TABS.map((tab) => {
          const tabCount = tab.value === "all" ? totalCount : (countByStatus.get(tab.value) ?? 0);
          const isActive = status === tab.value;
          return (
            <Link
              key={tab.value}
              href={`/events?status=${tab.value}${q ? `&q=${encodeURIComponent(q)}` : ""}`}
              className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px ${
                isActive
                  ? "border-neutral-900 text-neutral-900"
                  : "border-transparent text-neutral-500 hover:text-neutral-700"
              }`}
            >
              {tab.label} ({tabCount})
            </Link>
          );
        })}
      </div>

      <form method="get" action="/events" className="mb-4 flex items-center gap-2">
        <input type="hidden" name="status" value={status} />
        <input
          type="search"
          name="q"
          defaultValue={q}
          placeholder="Titel durchsuchen…"
          className="w-full max-w-xs rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
        />
        <button
          type="submit"
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
        >
          Suchen
        </button>
        {q && (
          <Link
            href={`/events?status=${status}`}
            className="text-sm font-medium text-neutral-500 hover:text-neutral-800"
          >
            Zurücksetzen
          </Link>
        )}
      </form>

      {error && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          Konnte Events nicht laden ({error.message}). Prüfe, ob{" "}
          <code className="font-mono">NEXT_PUBLIC_SUPABASE_URL</code> /{" "}
          <code className="font-mono">NEXT_PUBLIC_SUPABASE_ANON_KEY</code> gesetzt sind und das
          Schema migriert wurde (<code className="font-mono">supabase db push</code>).
        </div>
      )}

      {!error && (
        <BulkSelectionProvider>
          <BulkActionBar />
          <div className="overflow-hidden rounded-lg border border-neutral-200 bg-white">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="w-10 px-4 py-3">
                    <SelectAllCheckbox ids={data?.map((e) => e.id) ?? []} />
                  </th>
                  <th className="px-4 py-3 font-medium">Titel</th>
                  <th className="px-4 py-3 font-medium">Ort</th>
                  <th className="px-4 py-3 font-medium">Termin</th>
                  <th className="px-4 py-3 font-medium">Quelle</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {q && !data?.length ? (
                  <tr>
                    <td colSpan={7} className="px-4 py-10 text-center text-neutral-400">
                      Keine Veranstaltungen für „{q}“ gefunden.
                    </td>
                  </tr>
                ) : data?.length ? (
                  data.map((event) => (
                    <tr key={event.id} className="hover:bg-neutral-50">
                      <td className="px-4 py-3">
                        <RowCheckbox eventId={event.id} />
                      </td>
                      <td className="px-4 py-3 font-medium text-neutral-900">{event.title}</td>
                      <td className="px-4 py-3 text-neutral-600">{event.venues?.name ?? "—"}</td>
                      <td className="px-4 py-3 text-neutral-600 tabular-nums">
                        {new Date(event.start_datetime).toLocaleString("de-DE", {
                          dateStyle: "medium",
                          timeStyle: "short",
                        })}
                      </td>
                      <td className="px-4 py-3 text-neutral-500">{event.sources?.name ?? "manuell"}</td>
                      <td className="px-4 py-3">
                        <span className="rounded-full bg-neutral-100 px-2.5 py-1 text-xs font-medium text-neutral-700">
                          {STATUS_LABEL[event.status] ?? event.status}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center justify-end gap-4">
                          {event.status === "draft" && <PublishRowButton eventId={event.id} />}
                          <Link
                            href={`/events/${event.id}`}
                            className="text-sm font-medium text-neutral-700 hover:text-neutral-900"
                          >
                            Bearbeiten
                          </Link>
                        </div>
                      </td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan={7} className="px-4 py-10 text-center text-neutral-400">
                      {status === "all"
                        ? "Noch keine Veranstaltungen. Seed-Daten via "
                        : `Keine Veranstaltungen mit Status "${STATUS_LABEL[status] ?? status}". Seed-Daten via `}
                      <code className="font-mono">supabase db reset</code> laden oder Import starten.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="mt-4 flex items-center justify-between text-sm text-neutral-500">
              <span>
                Seite {page} von {totalPages} ({count} Ergebnis{count === 1 ? "" : "se"})
              </span>
              <div className="flex gap-2">
                {page > 1 && (
                  <Link
                    href={`/events?status=${status}&page=${page - 1}${q ? `&q=${encodeURIComponent(q)}` : ""}`}
                    className="rounded-md border border-neutral-300 px-3 py-1.5 font-medium text-neutral-700 hover:bg-neutral-50"
                  >
                    Zurück
                  </Link>
                )}
                {page < totalPages && (
                  <Link
                    href={`/events?status=${status}&page=${page + 1}${q ? `&q=${encodeURIComponent(q)}` : ""}`}
                    className="rounded-md border border-neutral-300 px-3 py-1.5 font-medium text-neutral-700 hover:bg-neutral-50"
                  >
                    Weiter
                  </Link>
                )}
              </div>
            </div>
          )}
        </BulkSelectionProvider>
      )}
    </div>
  );
}
