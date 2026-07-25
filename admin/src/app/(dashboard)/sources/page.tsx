import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

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
  active: "bg-emerald-50 text-emerald-700",
  paused: "bg-neutral-100 text-neutral-600",
  under_review: "bg-amber-50 text-amber-700",
  error: "bg-red-50 text-red-700",
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
            className="rounded-md border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-100"
          >
            Neue Quellen entdecken
          </Link>
          <Link
            href="/sources/onboard"
            className="rounded-md border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-100"
          >
            Neue Quelle testen
          </Link>
          <Link
            href="/sources/new"
            className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700"
          >
            Neu anlegen
          </Link>
        </div>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Quellen nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 overflow-hidden rounded-lg border border-neutral-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-3 font-medium">Name</th>
                <th className="px-4 py-3 font-medium">Typ</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Letzter Lauf</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {data?.length ? (
                data.map((source) => (
                  <tr key={source.id} className="hover:bg-neutral-50">
                    <td className="px-4 py-3 font-medium text-neutral-900">{source.name}</td>
                    <td className="px-4 py-3 text-neutral-600">{TYPE_LABEL[source.type] ?? source.type}</td>
                    <td className="px-4 py-3">
                      <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_STYLE[source.status] ?? ""}`}>
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
                      <Link href={`/sources/${source.id}`} className="text-sm font-medium text-neutral-700 hover:text-neutral-900">
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
      )}
    </div>
  );
}
