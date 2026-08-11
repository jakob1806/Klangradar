import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { markCodeFixTaskDone } from "./actions";
import { CopyPromptButton } from "./copy-prompt-button";

export const dynamic = "force-dynamic";

interface TaskRow {
  id: string;
  report_id: string;
  title: string;
  prompt: string;
  status: "pending" | "claimed" | "done";
  created_at: string;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

/** Nutzerwunsch: "bei erneut versuchen soll einfach eine KI diese fehler
 * durchgehen und beheben. das ist dann wie, als würde ich dir eine
 * chatnachricht mit der fehlerkorrektur schreiben." Vermutet der freiere
 * Retry-Fix (auto-fix-content-report, fixFreeform) einen Code-Bug statt
 * eines Datenproblems, kann die Edge Function das nicht selbst reparieren
 * (kein Repo-/Deploy-Zugriff zur Laufzeit) — stattdessen landet hier ein
 * fertiger, in sich geschlossener Auftragstext für Claude Code.
 */
export default async function CodeFixTasksPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("code_fix_tasks")
    .select("id, report_id, title, prompt, status, created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .returns<TaskRow[]>();

  return (
    <div className="p-8">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Code-Aufgaben für Claude Code</h1>
        <p className="mt-1 max-w-xl text-sm text-neutral-500">
          Wenn der freiere Fix-Versuch einer Nutzer-Meldung ("Erneut versuchen") vermutet, dass die Ursache ein Bug
          im Scraping-/Ingest-Code ist statt eines falschen Datenwerts, landet hier ein fertiger Auftragstext —
          Auftragstext kopieren und Claude Code damit beauftragen, danach hier abhaken.
        </p>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Aufgaben nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data && data.length > 0 ? (
            data.map((task) => (
              <div key={task.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="border border-purple-700 px-2 py-1 type-label !text-purple-700">Code-Bug vermutet</span>
                      <span className="text-xs text-neutral-400">{formatDate(task.created_at)}</span>
                    </div>
                    <p className="mt-2 text-sm font-medium text-neutral-900">{task.title}</p>
                    <pre className="mt-2 whitespace-pre-wrap rounded-md bg-neutral-50 p-3 text-xs text-neutral-700">{task.prompt}</pre>
                    <a href={`/content-reports`} className="mt-1 inline-block text-xs text-blue-700 hover:underline">
                      zugehörige Meldung in Nutzer-Meldungen ansehen
                    </a>
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-2">
                    <CopyPromptButton prompt={task.prompt} />
                    <ConfirmButton
                      action={markCodeFixTaskDone.bind(null, task.id)}
                      confirmMessage="Als erledigt markieren?"
                      label="Erledigt"
                      pendingLabel="…"
                      className="border-2 border-emerald-700 bg-white px-2.5 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
                    />
                  </div>
                </div>
              </div>
            ))
          ) : (
            <p className="text-sm text-neutral-500">Keine offenen Code-Aufgaben.</p>
          )}
        </div>
      )}
    </div>
  );
}
