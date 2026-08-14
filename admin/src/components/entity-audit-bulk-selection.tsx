"use client";

import { createContext, useContext, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  applyAllEntityAuditCorrections,
  resolveEntityAuditFlags,
} from "@/lib/entity-audit-actions";

const SelectionContext = createContext<{
  selected: Set<string>;
  toggle: (id: string) => void;
} | null>(null);

export function EntityAuditBulkSelection({ children, ids }: { children: React.ReactNode; ids: string[] }) {
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
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

  function applySelected() {
    const ids = [...selected];
    startTransition(async () => {
      try {
        const result = await applyAllEntityAuditCorrections(ids);
        setMessage(`${result.completed} übernommen${result.skipped ? `, ${result.skipped} ohne sicheren Vorschlag` : ""}${result.failed ? `, ${result.failed} fehlgeschlagen` : ""}.`);
        setSelected(new Set());
        router.refresh();
      } catch (error) {
        setMessage(error instanceof Error ? error.message : "Sammelkorrektur fehlgeschlagen.");
      }
    });
  }

  function resolveSelected() {
    if (!window.confirm(`${selected.size} ausgewählte Einträge als erledigt markieren?`)) return;
    const ids = [...selected];
    startTransition(async () => {
      try {
        const result = await resolveEntityAuditFlags(ids);
        setMessage(`${result.completed} als erledigt markiert.`);
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
        <div className="mt-6 flex items-center justify-between gap-3">
          <p className="text-xs text-neutral-500">
            {selected.size > 0 ? `${selected.size} von ${ids.length} ausgewählt` : `${ids.length} offene Treffer`}
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
          <button
            type="button"
            disabled={pending}
            onClick={applySelected}
            className="rounded-lg bg-violet-700 px-3 py-2 text-xs font-semibold text-white hover:bg-violet-800 disabled:opacity-50"
          >
            {pending ? "Verarbeitet…" : "KI-Korrekturen übernehmen"}
          </button>
          <button
            type="button"
            disabled={pending}
            onClick={resolveSelected}
            className="rounded-lg border border-emerald-300 bg-white px-3 py-2 text-xs font-semibold text-emerald-800 hover:bg-emerald-50 disabled:opacity-50"
          >
            Als erledigt markieren
          </button>
          <button type="button" onClick={() => setSelected(new Set())} className="px-2 py-2 text-xs text-neutral-500">
            Auswahl aufheben
          </button>
        </div>
      )}
      {message && selected.size === 0 && <p className="mt-3 text-center text-xs text-neutral-500">{message}</p>}
    </SelectionContext.Provider>
  );
}

export function EntityAuditSelectCheckbox({ id, label }: { id: string; label: string }) {
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
