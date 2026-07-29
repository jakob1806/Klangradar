"use client";

// Macht die "nur X/N Termine"-Anzeige tatsächlich bearbeitbar (Nutzeranfrage:
// "steht zwar da, dass eine Person nur 1/3 Termine macht, aber man kann das
// nicht ändern") — Klick blendet eine Checkbox-Liste aller Gruppentermine
// ein, vorbelegt mit den aktuell verknüpften; Speichern ruft die jeweilige
// setXEventMembership-Action mit der ausgewählten Teilmenge auf.

import { useState, useTransition } from "react";
import { EventChecklist, type ChecklistEvent } from "./event-checklist";

export function MembershipEditor({
  events,
  checkedIds,
  onSave,
}: {
  events: ChecklistEvent[];
  checkedIds: Set<string>;
  onSave: (eventIds: string[]) => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(checkedIds);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="text-xs font-medium text-neutral-500 hover:text-neutral-800"
      >
        Termine bearbeiten
      </button>
    );
  }

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <div className="mt-2 flex flex-col gap-2 rounded-md border border-neutral-200 bg-neutral-50 p-2">
      <div className="flex flex-col gap-1">
        {events.map((e) => (
          <label key={e.id} className="flex items-center gap-2 text-xs text-neutral-700">
            <input
              type="checkbox"
              checked={selected.has(e.id)}
              onChange={() => toggle(e.id)}
              className="h-3.5 w-3.5 rounded border-neutral-300"
            />
            {e.label}
          </label>
        ))}
      </div>
      <div className="flex items-center gap-3">
        <button
          type="button"
          disabled={pending}
          onClick={() => {
            setError(null);
            startTransition(async () => {
              try {
                await onSave(Array.from(selected));
                setOpen(false);
              } catch (err) {
                setError(err instanceof Error ? err.message : "Speichern fehlgeschlagen.");
              }
            });
          }}
          className="rounded-md bg-neutral-900 px-2.5 py-1 text-xs font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
        >
          {pending ? "Speichere…" : "Speichern"}
        </button>
        <button
          type="button"
          onClick={() => {
            setSelected(checkedIds);
            setOpen(false);
          }}
          className="text-xs font-medium text-neutral-500 hover:text-neutral-800"
        >
          Abbrechen
        </button>
      </div>
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  );
}

// Re-export für page.tsx, damit dort nicht zwei Importe nötig sind.
export type { ChecklistEvent };
export { EventChecklist };
