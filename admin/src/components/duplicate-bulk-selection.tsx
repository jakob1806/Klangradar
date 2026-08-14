"use client";

import { createContext, useContext, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

const SelectionContext = createContext<{
  selected: Set<string>;
  toggle: (id: string) => void;
} | null>(null);

/** Mehrfachauswahl für einen Duplikate-Reiter (Werk/Personen/Ensemble/Venue/
 * Veranstaltungen) — Nutzervorgabe "man kann jeweils mehrere Duplikate
 * auswählen, und dann die Optionen bei diesen durchführen". Bewusst NUR
 * "als unterschiedlich markieren" als Sammelaktion: Zusammenführen braucht
 * pro Paar eine Entscheidung, welche der beiden Versionen bleibt, das lässt
 * sich nicht gefahrlos automatisieren — bleibt eine Einzelfall-Aktion direkt
 * an der jeweiligen Karte. `onDismissMany` ist die typ-spezifische
 * Server-Action (z.B. resolvePersonDuplicatesAsDistinct). */
export function DuplicateBulkSelection({
  children,
  ids,
  onDismissMany,
}: {
  children: React.ReactNode;
  ids: string[];
  onDismissMany: (ids: string[]) => Promise<{ completed: number }>;
}) {
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const value = useMemo(
    () => ({
      selected,
      toggle: (id: string) =>
        setSelected((current) => {
          const next = new Set(current);
          if (next.has(id)) next.delete(id);
          else next.add(id);
          return next;
        }),
    }),
    [selected],
  );

  function dismissSelected() {
    setConfirming(false);
    const idsToDismiss = [...selected];
    startTransition(async () => {
      try {
        const result = await onDismissMany(idsToDismiss);
        setMessage(`${result.completed} als unterschiedlich markiert.`);
        setSelected(new Set());
        router.refresh();
      } catch (error) {
        setMessage(error instanceof Error ? error.message : "Sammelaktion fehlgeschlagen.");
      }
    });
  }

  return (
    <SelectionContext.Provider value={value}>
      {ids.length > 0 && (
        <div className="mt-4 flex items-center justify-between gap-3">
          <p className="text-xs text-neutral-500">
            {selected.size > 0 ? `${selected.size} von ${ids.length} ausgewählt` : `${ids.length} offene Kandidaten`}
          </p>
          <button
            type="button"
            onClick={() => setSelected(selected.size === ids.length ? new Set() : new Set(ids))}
            className="rounded-lg border border-neutral-200 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:bg-neutral-50"
          >
            {selected.size === ids.length ? "Auswahl aufheben" : "Alle auswählen"}
          </button>
        </div>
      )}
      {children}
      {selected.size > 0 && (
        <div className="sticky bottom-4 z-20 mx-auto mt-4 flex max-w-3xl flex-wrap items-center gap-2 rounded-2xl border border-neutral-200 bg-white/95 p-3 shadow-xl backdrop-blur">
          <span className="mr-auto text-sm font-semibold text-neutral-900">{selected.size} ausgewählt</span>
          {confirming ? (
            <span className="flex items-center gap-2 text-xs">
              <span className="text-neutral-600">Wirklich als unterschiedlich markieren?</span>
              <button
                type="button"
                disabled={pending}
                onClick={dismissSelected}
                className="font-semibold text-neutral-900 hover:text-black disabled:opacity-50"
              >
                Ja
              </button>
              <button
                type="button"
                disabled={pending}
                onClick={() => setConfirming(false)}
                className="font-semibold text-neutral-500 hover:text-neutral-700 disabled:opacity-50"
              >
                Abbrechen
              </button>
            </span>
          ) : (
            <button
              type="button"
              disabled={pending}
              onClick={() => setConfirming(true)}
              className="rounded-lg border border-neutral-300 bg-white px-3 py-2 text-xs font-semibold text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
            >
              {pending ? "Verarbeitet…" : "Als unterschiedlich markieren"}
            </button>
          )}
          <button type="button" onClick={() => setSelected(new Set())} className="px-2 py-2 text-xs text-neutral-500">
            Auswahl aufheben
          </button>
        </div>
      )}
      {message && selected.size === 0 && <p className="mt-3 text-center text-xs text-neutral-500">{message}</p>}
    </SelectionContext.Provider>
  );
}

export function DuplicateSelectCheckbox({ id, label }: { id: string; label: string }) {
  const context = useContext(SelectionContext);
  if (!context) return null;
  return (
    <label className="flex cursor-pointer items-center gap-2 text-xs text-neutral-500">
      <input
        type="checkbox"
        checked={context.selected.has(id)}
        onChange={() => context.toggle(id)}
        className="h-4 w-4 rounded border-neutral-300 accent-[#0071e3]"
      />
      <span className="sr-only">{label} auswählen</span>
      Auswählen
    </label>
  );
}
