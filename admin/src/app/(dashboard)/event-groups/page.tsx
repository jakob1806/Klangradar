import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { createEventGroup, deleteEventGroup } from "./actions";
import { suggestEventGroups } from "./suggestions";

export const dynamic = "force-dynamic";

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

interface GroupRow {
  id: string;
  title: string;
  created_at: string;
  events: { id: string; title: string; start_datetime: string }[];
}

export default async function EventGroupsPage() {
  const supabase = await createClient();
  const [{ data: groups }, suggestions] = await Promise.all([
    supabase
      .from("programs")
      .select("id, title, created_at, events(id, title, start_datetime)")
      .order("created_at", { ascending: false })
      .returns<GroupRow[]>(),
    suggestEventGroups(),
  ]);

  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Event-Gruppen</h1>
      <p className="mt-1 max-w-2xl text-sm text-neutral-500">
        Mehrere Termine derselben Produktion (z.&nbsp;B. Opernfestspiele-Vorstellungen an mehreren Tagen mit
        gleichem Programm) zu einer Gruppe zusammenfassen — Werke &amp; Mitwirkende werden dann für die ganze
        Gruppe auf einmal gepflegt statt pro Event einzeln.
      </p>

      <section className="mt-8">
        <h2 className="text-sm font-semibold text-neutral-900">
          Vorschläge {suggestions.length > 0 && `(${suggestions.length})`}
        </h2>
        <p className="mt-1 text-xs text-neutral-500">
          Ungruppierte, geplante Events mit identischem Titel und höchstens 14 Tagen Abstand zwischen den
          Terminen.
        </p>

        {suggestions.length === 0 ? (
          <div className="mt-3 border-2 border-dashed border-neutral-300 bg-white px-4 py-8 text-center text-sm text-neutral-400">
            Aktuell keine Vorschläge.
          </div>
        ) : (
          <div className="mt-3 flex flex-col gap-3">
            {suggestions.map((s) => (
              <div key={s.key} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <div className="flex items-center justify-between gap-4">
                  <p className="font-medium text-neutral-900">{s.title}</p>
                  <form action={createEventGroup.bind(null, s.title, s.events.map((e) => e.id))}>
                    <button
                      type="submit"
                      className="rounded-full bg-[#0071e3] px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
                    >
                      Gruppe anlegen ({s.events.length})
                    </button>
                  </form>
                </div>
                <ul className="mt-2 flex flex-col gap-1 text-sm text-neutral-600">
                  {s.events.map((e) => (
                    <li key={e.id}>
                      {formatDate(e.start_datetime)}
                      {e.venueName && <span className="text-neutral-400"> · {e.venueName}</span>}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="mt-10">
        <h2 className="text-sm font-semibold text-neutral-900">
          Bestehende Gruppen {groups && groups.length > 0 && `(${groups.length})`}
        </h2>

        {!groups || groups.length === 0 ? (
          <div className="mt-3 border-2 border-dashed border-neutral-300 bg-white px-4 py-8 text-center text-sm text-neutral-400">
            Noch keine Gruppen angelegt.
          </div>
        ) : (
          <div className="mt-3 flex flex-col gap-3">
            {groups.map((g) => (
              <div key={g.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <div className="flex items-center justify-between gap-4">
                  <Link href={`/event-groups/${g.id}`} className="font-medium text-neutral-900 hover:underline">
                    {g.title}
                  </Link>
                  <div className="flex items-center gap-3">
                    <span className="text-xs text-neutral-400">
                      {g.events.length} Termin{g.events.length === 1 ? "" : "e"}
                    </span>
                    <ConfirmButton
                      action={deleteEventGroup.bind(null, g.id)}
                      confirmMessage={`Gruppe "${g.title}" auflösen? Die Events selbst bleiben erhalten, nur die Verknüpfung wird entfernt.`}
                      label="Auflösen"
                      pendingLabel="Löse auf…"
                      className="text-sm font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
                    />
                  </div>
                </div>
                <ul className="mt-2 flex flex-col gap-1 text-sm text-neutral-600">
                  {g.events.map((e) => (
                    <li key={e.id}>
                      {e.title} · {formatDate(e.start_datetime)}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
