import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { TableSearchFilter } from "@/components/table-search-filter";

export const dynamic = "force-dynamic";

interface SourceRow {
  id: string;
  name: string;
  type: string;
  status: string;
  last_run_at: string | null;
  consecutive_failures: number;
}

const TYPE_LABEL: Record<string, string> = {
  manual: "Manuell",
  schema_org: "Schema.org",
  ical: "iCal",
  rss: "RSS",
  api: "API",
  scrape: "Scraping",
};

const STATUS_STYLE: Record<string, string> = {
  active: "border-emerald-700 !text-emerald-700",
  paused: "border-neutral-300 !text-neutral-500",
  under_review: "border-amber-700 !text-amber-700",
  error: "border-red-700 !text-red-700",
};

export default async function SourcesPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("sources")
    .select("id, name, type, status, last_run_at, consecutive_failures")
    .order("name")
    .returns<SourceRow[]>();

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Datenquellen & Import</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Schema.org-, iCal-, RSS- und Scraping-Quellen verwalten. Ein täglicher Cron-Job (2:00 Uhr UTC / 4:00 Uhr
            Sommerzeit, siehe <code>cron.job</code> in Supabase) ruft automatisch alle aktiven Quellen ab —
            &bdquo;Letzter Lauf&rdquo; unten zeigt das Ergebnis. Eine neu angelegte Quelle wird beim nächsten planmäßigen
            Lauf mit erfasst; ein sofortiger Einzellauf lässt sich über &bdquo;Jetzt ausführen&rdquo; auf der jeweiligen
            Quellen-Seite auslösen.
          </p>
        </div>
        <div className="flex gap-3">
          <Link
            href="/sources/discover"
            className="rounded-full glass-pill px-4 py-2 text-sm font-medium text-[#1d1d1f] transition-colors hover:bg-black/[0.04]"
          >
            Neue Quellen entdecken
          </Link>
          <Link
            href="/sources/onboard"
            className="rounded-full glass-pill px-4 py-2 text-sm font-medium text-[#1d1d1f] transition-colors hover:bg-black/[0.04]"
          >
            Neue Quelle testen
          </Link>
          <Link
            href="/sources/new"
            className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
          >
            Neu anlegen
          </Link>
        </div>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Quellen nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6">
        <TableSearchFilter containerId="sources-table" placeholder="Name durchsuchen…" />
        <div id="sources-table" className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
          <table className="w-full text-sm">
            <thead className="border-b border-black/[0.06] text-left">
              <tr>
                <th className="type-label px-4 py-3">Name</th>
                <th className="type-label px-4 py-3">Typ</th>
                <th className="type-label px-4 py-3">Status</th>
                <th className="type-label px-4 py-3">Letzter Lauf</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-200">
              {data?.length ? (
                data.map((source) => (
                  <tr key={source.id} data-search={source.name.toLowerCase()} className="hover:bg-neutral-50">
                    <td className="px-4 py-3 font-medium text-neutral-900">{source.name}</td>
                    <td className="px-4 py-3 text-neutral-600">{TYPE_LABEL[source.type] ?? source.type}</td>
                    <td className="px-4 py-3">
                      <span className={`type-label border px-2 py-1 ${STATUS_STYLE[source.status] ?? "border-neutral-300 !text-neutral-500"}`}>
                        {source.status}
                        {source.consecutive_failures > 0 ? ` · ${source.consecutive_failures}x fehlgeschlagen` : ""}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-neutral-600 tabular-nums">
                      {source.last_run_at
                        ? new Date(source.last_run_at).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" })
                        : "—"}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link href={`/sources/${source.id}`} className="text-sm font-medium text-neutral-700 hover:text-[#0071e3]">
                        Bearbeiten
                      </Link>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={5} className="px-4 py-10 text-center text-neutral-400">
                    Noch keine Datenquellen erfasst.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        </div>
      )}
    </div>
  );
}
