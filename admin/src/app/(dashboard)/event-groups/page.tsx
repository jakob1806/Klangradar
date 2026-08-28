import { ConfirmButton } from "@/components/confirm-button";
import { createClient } from "@/lib/supabase/server";
import { mergeEventGroupsBatch } from "./actions";
import { suggestEventGroups, suggestGroupMerges } from "./suggestions";
import { ExistingGroupsList, type GroupRow } from "./existing-groups-list";
import { SuggestionCard } from "./suggestion-card";
import { loadWorksByEventId } from "@/lib/event-works";

export const dynamic = "force-dynamic";

interface RawGroupRow {
  id: string;
  title: string;
  created_at: string;
  events: { id: string; title: string; start_datetime: string; venues: { name: string } | null }[];
}

export default async function EventGroupsPage() {
  const supabase = await createClient();
  const [{ data: rawGroups }, suggestions, mergeSuggestions] = await Promise.all([
    supabase
      .from("programs")
      .select("id, title, created_at, events(id, title, start_datetime, venues(name))")
      .order("created_at", { ascending: false })
      .returns<RawGroupRow[]>(),
    suggestEventGroups(),
    suggestGroupMerges(),
  ]);

  // Nutzerwunsch: "bei eventgruppen muss der standort angezeigt werden
  // (pro veranstaltung nicht pro gruppe), auch wenn eine gruppe schon
  // besteht. dann auch bei jeder veranstaltung das programm." — city-Schutz
  // gilt zwar pro Gruppe (assertSameCity), der konkrete Venue-Name kann
  // innerhalb einer Gruppe trotzdem variieren, deshalb pro Termin statt nur
  // einmal pro Gruppe anzeigen. Werke aus event_works, siehe suggestions.ts
  // für denselben Ansatz bei den noch ungruppierten Vorschlägen.
  const allEventIds = (rawGroups ?? []).flatMap((g) => g.events.map((e) => e.id));
  const worksByEventId = await loadWorksByEventId(supabase, allEventIds);
  const groups: GroupRow[] = (rawGroups ?? []).map((g) => ({
    ...g,
    events: g.events.map((e) => ({ ...e, works: worksByEventId.get(e.id) ?? [] })),
  }));

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
              <SuggestionCard key={s.key} suggestion={s} />
            ))}
          </div>
        )}
      </section>

      <section className="mt-10">
        <h2 className="text-sm font-semibold text-neutral-900">
          Zusammenführungs-Vorschläge {mergeSuggestions.length > 0 && `(${mergeSuggestions.length})`}
        </h2>
        <p className="mt-1 text-xs text-neutral-500">
          Bereits angelegte Gruppen mit gleichem Titel und mindestens einem gemeinsamen Veranstaltungsort — hier
          greift die 14-Tage-Grenze der Vorschläge oben bewusst nicht, da es sich nicht um noch ungruppierte
          Einzeltermine, sondern um schon bestehende Serien derselben Produktion handelt.
        </p>

        {mergeSuggestions.length === 0 ? (
          <div className="mt-3 border-2 border-dashed border-neutral-300 bg-white px-4 py-8 text-center text-sm text-neutral-400">
            Aktuell keine Vorschläge.
          </div>
        ) : (
          <div className="mt-3 flex flex-col gap-3">
            {mergeSuggestions.map((s) => (
              <div key={s.key} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                <div className="flex items-center justify-between gap-4">
                  <div>
                    <p className="font-medium text-neutral-900">{s.title}</p>
                    {s.venueName && <p className="text-xs text-neutral-400">{s.venueName}</p>}
                  </div>
                  <ConfirmButton
                    action={mergeEventGroupsBatch.bind(null, s.targetGroupId, s.sourceGroupIds)}
                    confirmMessage={`${s.groups.length} Gruppen zu "${s.targetTitle}" zusammenführen?`}
                    label={`Zusammenführen (${s.groups.length} Gruppen)`}
                    pendingLabel="Führe zusammen…"
                    className="rounded-lg bg-[#0071e3] px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
                  />
                </div>
                <ul className="mt-2 flex flex-col gap-1 text-sm text-neutral-600">
                  {s.groups.map((g) => (
                    <li key={g.id}>
                      {g.title} · {g.eventCount} Termin{g.eventCount === 1 ? "" : "e"}
                      {g.id === s.targetGroupId && <span className="text-neutral-400"> (Ziel)</span>}
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
          Bestehende Gruppen {groups.length > 0 && `(${groups.length})`}
        </h2>

        <ExistingGroupsList groups={groups} />
      </section>
    </div>
  );
}
