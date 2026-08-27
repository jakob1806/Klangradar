import { ConfirmButton } from "@/components/confirm-button";
import { DeleteButton } from "@/components/delete-button";
import { createClient } from "@/lib/supabase/server";
import { createTodo, deleteTodo, markTodoDone, reopenTodo } from "./actions";

export const dynamic = "force-dynamic";

interface TodoRow {
  id: string;
  title: string;
  description: string;
  status: "open" | "done";
  created_by: string | null;
  created_at: string;
  done_at: string | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export default async function TodosPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("todos")
    .select("id, title, description, status, created_by, created_at, done_at")
    .order("created_at", { ascending: false })
    .returns<TodoRow[]>();

  const open = (data ?? []).filter((todo) => todo.status === "open");
  const done = (data ?? []).filter((todo) => todo.status === "done");

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">To-Dos</h1>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Freie Aufgabenliste für alles, was sonst nirgends erfasst wird — z.B. &bdquo;Veranstaltung X hat ein falsches
        Bild&ldquo;. Titel kurz, Beschreibung so genau wie möglich.
      </p>

      <form action={createTodo} className="mt-6 flex flex-col gap-3 rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
        <input
          name="title"
          required
          placeholder="Titel"
          className="rounded-lg border border-black/10 px-3 py-2 text-sm outline-none focus:border-[#0071e3]"
        />
        <textarea
          name="description"
          required
          rows={3}
          placeholder="Genaue Beschreibung"
          className="rounded-lg border border-black/10 px-3 py-2 text-sm outline-none focus:border-[#0071e3]"
        />
        <button className="self-start rounded-lg bg-[#0071e3] px-4 py-2 text-sm font-medium text-white hover:bg-[#0068d1]">
          To-Do anlegen
        </button>
      </form>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte To-Dos nicht laden: {error.message}</p>}

      {!error && (
        <>
          <h2 className="mt-8 text-sm font-semibold text-neutral-700">Offen ({open.length})</h2>
          <div className="mt-3 flex flex-col gap-3">
            {open.length ? (
              open.map((todo) => (
                <div key={todo.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="text-sm font-medium text-neutral-900">{todo.title}</p>
                        <span className="text-xs text-neutral-400">{formatDate(todo.created_at)}</span>
                        {todo.created_by && <span className="text-xs text-neutral-400">· {todo.created_by}</span>}
                      </div>
                      <p className="mt-2 whitespace-pre-wrap text-sm text-neutral-600">{todo.description}</p>
                    </div>
                    <div className="flex shrink-0 items-center gap-3">
                      <ConfirmButton
                        action={markTodoDone.bind(null, todo.id)}
                        confirmMessage="Als erledigt markieren?"
                        label="Erledigt"
                        pendingLabel="…"
                        className="border-2 border-emerald-700 bg-white px-2.5 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
                      />
                      <DeleteButton action={deleteTodo.bind(null, todo.id)} confirmMessage={`To-Do "${todo.title}" löschen?`} />
                    </div>
                  </div>
                </div>
              ))
            ) : (
              <p className="text-sm text-neutral-500">Keine offenen To-Dos.</p>
            )}
          </div>

          {done.length > 0 && (
            <>
              <h2 className="mt-8 text-sm font-semibold text-neutral-700">Erledigt ({done.length})</h2>
              <div className="mt-3 flex flex-col gap-3">
                {done.map((todo) => (
                  <div key={todo.id} className="rounded-xl border border-black/[0.06] bg-neutral-50 p-4 opacity-70">
                    <div className="flex flex-wrap items-start justify-between gap-4">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="text-sm font-medium text-neutral-700 line-through">{todo.title}</p>
                          <span className="text-xs text-neutral-400">
                            erledigt {todo.done_at ? formatDate(todo.done_at) : ""}
                          </span>
                        </div>
                        <p className="mt-2 whitespace-pre-wrap text-sm text-neutral-500">{todo.description}</p>
                      </div>
                      <div className="flex shrink-0 items-center gap-3">
                        <ConfirmButton
                          action={reopenTodo.bind(null, todo.id)}
                          confirmMessage="Wieder öffnen?"
                          label="Wieder öffnen"
                          pendingLabel="…"
                          className="border border-black/10 bg-white px-2.5 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-100 disabled:opacity-50"
                        />
                        <DeleteButton action={deleteTodo.bind(null, todo.id)} confirmMessage={`To-Do "${todo.title}" löschen?`} />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}
