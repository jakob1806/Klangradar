import { createClient } from "@/lib/supabase/server";
import { DeleteButton } from "@/components/delete-button";
import { dismissReport } from "./actions";

export const dynamic = "force-dynamic";

interface ReportRow {
  id: number;
  source: string | null;
  message: string;
  context: Record<string, unknown>;
  created_at: string;
}

export default async function ReportsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("error_reports")
    .select("id, source, message, context, created_at")
    .order("created_at", { ascending: false })
    .limit(100)
    .returns<ReportRow[]>();

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Fehlerberichte</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Von der App gemeldete Fehler und Datenqualitätsprobleme.
      </p>

      {error && (
        <p className="mt-6 text-sm text-amber-700">Konnte Fehlerberichte nicht laden: {error.message}</p>
      )}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data?.length ? (
            data.map((report) => (
              <div key={report.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="flex items-center gap-2">
                      {report.source && (
                        <span className="rounded-full bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-700">
                          {report.source}
                        </span>
                      )}
                      <span className="text-xs text-neutral-400">
                        {new Date(report.created_at).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" })}
                      </span>
                    </div>
                    <p className="mt-2 text-sm font-medium text-neutral-900">{report.message}</p>
                    {Object.keys(report.context ?? {}).length > 0 && (
                      <pre className="mt-2 overflow-x-auto rounded-md bg-neutral-50 p-2 text-xs text-neutral-600">
                        {JSON.stringify(report.context, null, 2)}
                      </pre>
                    )}
                  </div>
                  <DeleteButton action={dismissReport.bind(null, report.id)} confirmMessage="Fehlerbericht als erledigt entfernen?" />
                </div>
              </div>
            ))
          ) : (
            <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
              Keine Fehlerberichte — alles sauber.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
