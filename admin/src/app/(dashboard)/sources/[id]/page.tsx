import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DeleteButton } from "@/components/delete-button";
import { SubmitButton } from "@/components/submit-button";
import { deleteSource, runSourceNow, updateSource } from "../actions";
import { SourceForm, type SourceFormValues } from "../source-form";

interface IngestionRunRow {
  id: string;
  started_at: string;
  finished_at: string | null;
  status: string;
  events_found: number;
  events_created: number;
  events_updated: number;
  events_flagged_for_review: number;
  errors: unknown[] | null;
}

const RUN_STATUS_STYLE: Record<string, string> = {
  running: "bg-neutral-100 text-neutral-600",
  success: "bg-emerald-50 text-emerald-700",
  partial: "bg-amber-50 text-amber-700",
  failed: "bg-red-50 text-red-700",
  skipped_unchanged: "bg-blue-50 text-blue-700",
};

function truncate(text: string, max = 140) {
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

export default async function EditSourcePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data, error }, { data: venues }, { data: organizers }, { data: persons }, { data: ensembles }, { data: runs }] =
    await Promise.all([
      supabase
        .from("sources")
        .select(
          "name, type, url, venue_id, organizer_id, person_id, ensemble_id, crawl_frequency_minutes, legal_basis, status, config",
        )
        .eq("id", id)
        .maybeSingle<SourceFormValues>(),
      supabase.from("venues").select("id, name").order("name"),
      supabase.from("organizers").select("id, name").order("name"),
      supabase.from("persons").select("id, full_name").order("full_name"),
      supabase.from("ensembles").select("id, name").order("name"),
      supabase
        .from("ingestion_runs")
        .select("id, started_at, finished_at, status, events_found, events_created, events_updated, events_flagged_for_review, errors")
        .eq("source_id", id)
        .order("started_at", { ascending: false })
        .limit(10)
        .returns<IngestionRunRow[]>(),
    ]);

  if (error || !data) notFound();

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{data.name} bearbeiten</h1>
        <div className="flex items-center gap-4">
          <form action={runSourceNow.bind(null, id)}>
            <SubmitButton pendingLabel="Wird ausgeführt…">Jetzt ausführen</SubmitButton>
          </form>
          <DeleteButton action={deleteSource.bind(null, id)} confirmMessage={`"${data.name}" wirklich löschen?`} />
        </div>
      </div>
      <div className="mt-6">
        <SourceForm
          action={updateSource.bind(null, id)}
          initial={data}
          venues={venues ?? []}
          organizers={organizers ?? []}
          persons={persons ?? []}
          ensembles={ensembles ?? []}
        />
      </div>

      <div className="mt-10">
        <h2 className="text-sm font-semibold tracking-tight text-neutral-900">Letzte Läufe</h2>
        <div className="mt-3 overflow-hidden rounded-lg border border-neutral-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-3 font-medium">Gestartet</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Events</th>
                <th className="px-4 py-3 font-medium">Fehler</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {runs?.length ? (
                runs.map((run) => (
                  <tr key={run.id}>
                    <td className="px-4 py-3 text-neutral-600 tabular-nums">
                      {new Date(run.started_at).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" })}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${RUN_STATUS_STYLE[run.status] ?? ""}`}>
                        {run.status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-neutral-600 tabular-nums">
                      {run.events_found} gefunden · {run.events_created} neu · {run.events_updated} aktualisiert
                      {run.events_flagged_for_review > 0 ? ` · ${run.events_flagged_for_review} markiert` : ""}
                    </td>
                    <td className="px-4 py-3 text-neutral-600">
                      {Array.isArray(run.errors) && run.errors.length > 0 ? (
                        <details>
                          <summary className="cursor-pointer text-amber-700">{run.errors.length} Fehler</summary>
                          <ul className="mt-1 max-w-xs list-disc space-y-1 pl-4 text-xs text-neutral-500">
                            {run.errors.slice(0, 2).map((e, i) => (
                              <li key={i} className="break-words">
                                {truncate(typeof e === "string" ? e : JSON.stringify(e))}
                              </li>
                            ))}
                          </ul>
                        </details>
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={4} className="px-4 py-10 text-center text-neutral-400">
                    Noch keine Läufe.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
