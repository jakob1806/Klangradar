"use client";

import { useState, useTransition } from "react";
import { ConfirmButton } from "@/components/confirm-button";
import { createEventGroup, dismissEventGroupSuggestion } from "./actions";
import { formatMunichDateTime } from "@/lib/munich-time";
import type { SuggestedGroup } from "./suggestions";

/** Nutzerwunsch: "bei den eventgruppen soll man mehrere auswählen können
 * und diese direkt entweder ablehnen oder als gruppe anlegen lassen" —
 * jede Aufführung innerhalb eines Vorschlags ist einzeln abwählbar (z.B.
 * wenn der Titel zwar identisch ist, aber ein Termin nicht wirklich zur
 * Serie gehört), danach wirkt "Als Gruppe anlegen"/"Ablehnen" nur auf die
 * gerade ausgewählte Teilmenge. Client-Komponente, weil die Auswahl
 * interaktiv bleiben muss (native Checkboxen reichen dafür nicht, da
 * "Ablehnen" eine Bestätigung über ConfirmButton braucht). */
export function SuggestionCard({ suggestion }: { suggestion: SuggestedGroup }) {
  const [checked, setChecked] = useState<Set<string>>(new Set(suggestion.events.map((e) => e.id)));
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function toggle(id: string) {
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const selectedIds = suggestion.events.filter((e) => checked.has(e.id)).map((e) => e.id);

  function handleCreate() {
    setError(null);
    startTransition(async () => {
      try {
        await createEventGroup(suggestion.title, selectedIds);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Gruppe anlegen fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="font-medium text-neutral-900">{suggestion.title}</p>
        <div className="flex items-center gap-2">
          <button
            type="button"
            disabled={pending || selectedIds.length < 2}
            onClick={handleCreate}
            className="rounded-lg bg-[#0071e3] px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
          >
            {pending ? "Lege an…" : `Ausgewählte als Gruppe anlegen (${selectedIds.length})`}
          </button>
          <ConfirmButton
            action={() => dismissEventGroupSuggestion(selectedIds)}
            confirmMessage={`${selectedIds.length} ausgewählte Termine ablehnen?`}
            label="Ausgewählte ablehnen"
            pendingLabel="Lehne ab…"
            className="rounded-lg border border-black/10 px-3 py-1.5 text-sm font-medium text-neutral-600 transition-colors hover:bg-black/[0.04] disabled:opacity-50"
          />
        </div>
      </div>
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
      <ul className="mt-2 flex flex-col gap-1 text-sm text-neutral-600">
        {suggestion.events.map((e) => (
          <li key={e.id} className="flex items-start gap-2">
            <input
              type="checkbox"
              checked={checked.has(e.id)}
              onChange={() => toggle(e.id)}
              className="mt-1 accent-[#0071e3]"
            />
            <span>
              {formatMunichDateTime(e.start_datetime)}
              {e.venueName && <span className="text-neutral-400"> · {e.venueName}</span>}
              {e.works.length > 0 && (
                <details className="ml-1 inline-block align-middle">
                  <summary className="inline cursor-pointer text-xs font-medium text-[#0071e3]">Programm</summary>
                  <span className="ml-1 text-xs text-neutral-500">{e.works.join(" · ")}</span>
                </details>
              )}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
