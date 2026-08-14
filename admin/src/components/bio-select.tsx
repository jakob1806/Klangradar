"use client";

// Mehrfachauswahl für Personen/Ensembles/Venues-Listen, um mehrere auf
// einmal in den KI-Bio-Recherche-Workflow zu schicken (Nutzeranfrage: "füge
// hinzu, dass man mehrere jeweils auswählen kann und dann mithilfe von KI
// nach einer Bio suchen kann"). Bewusst EIN generischer Baustein statt drei
// fast identischer Kopien für Personen/Ensembles/Venues — nur `entityType`
// unterscheidet sich, der Rest (Auswahl-State, Bulk-Bar, Navigation zum
// Workflow) ist identisch.

import Link from "next/link";
import { createContext, useContext, useState, useTransition, type ReactNode } from "react";

type EntityType = "person" | "ensemble" | "venue";

interface SelectionContextValue {
  selected: Set<string>;
  toggle: (id: string) => void;
  setAll: (ids: string[], checked: boolean) => void;
  replaceSelection: (ids: string[]) => void;
  clear: () => void;
}

const SelectionContext = createContext<SelectionContextValue | null>(null);

function useSelection() {
  const ctx = useContext(SelectionContext);
  if (!ctx) throw new Error("useSelection must be used within BioSelectionProvider");
  return ctx;
}

export function BioSelectionProvider({ children }: { children: ReactNode }) {
  const [selected, setSelected] = useState<Set<string>>(new Set());

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function setAll(ids: string[], checked: boolean) {
    setSelected((prev) => {
      const next = new Set(prev);
      for (const id of ids) {
        if (checked) next.add(id);
        else next.delete(id);
      }
      return next;
    });
  }

  function replaceSelection(ids: string[]) {
    setSelected(new Set(ids));
  }

  function clear() {
    setSelected(new Set());
  }

  return (
    <SelectionContext.Provider value={{ selected, toggle, setAll, replaceSelection, clear }}>
      {children}
    </SelectionContext.Provider>
  );
}

export function BioRowCheckbox({ id }: { id: string }) {
  const { selected, toggle } = useSelection();
  return (
    <input
      type="checkbox"
      className="h-4 w-4 rounded border-neutral-300"
      checked={selected.has(id)}
      onChange={() => toggle(id)}
      aria-label="Auswählen"
    />
  );
}

export function BioSelectAllCheckbox({ ids }: { ids: string[] }) {
  const { selected, setAll } = useSelection();
  const allSelected = ids.length > 0 && ids.every((id) => selected.has(id));
  return (
    <input
      type="checkbox"
      className="h-4 w-4 rounded border-neutral-300"
      checked={allSelected}
      onChange={(e) => setAll(ids, e.target.checked)}
      aria-label="Alle auswählen"
    />
  );
}

/** Nutzeranfrage: "man soll die mgl. haben, nur alle auzuwählen, die keine
 * bio besitzen" — ersetzt die aktuelle Auswahl durch genau die IDs ohne Bio. */
export function BioSelectMissingButton({ ids }: { ids: string[] }) {
  const { replaceSelection } = useSelection();
  if (ids.length === 0) return null;
  return (
    <button
      type="button"
      onClick={() => replaceSelection(ids)}
      className="text-xs font-medium text-neutral-500 underline hover:text-neutral-800"
    >
      Alle ohne Bio auswählen ({ids.length})
    </button>
  );
}

/** Sichtbarer Hinweis, ob bereits eine Bio/Beschreibung vorliegt —
 * Nutzeranfrage: "alle, die bereits eine bio haben, sollen sichtbar zeigen,
 * dass sie eine besitzen". */
export function BioStatusBadge({ hasBio }: { hasBio: boolean }) {
  return (
    <span
      className={`rounded-full px-2.5 py-1 text-xs font-medium ${
        hasBio ? "bg-blue-50 text-blue-700" : "bg-neutral-100 text-neutral-400"
      }`}
    >
      {hasBio ? "Bio vorhanden" : "Keine Bio"}
    </span>
  );
}

export function BioResearchBar({
  entityType,
  bulkDeleteAction,
  bulkSetVerifiedAction,
}: {
  entityType: EntityType;
  bulkDeleteAction?: (ids: string[]) => Promise<void>;
  bulkSetVerifiedAction?: (ids: string[], verified: boolean) => Promise<void>;
}) {
  const { selected, clear } = useSelection();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  if (selected.size === 0) return null;

  const ids = Array.from(selected);
  const idsParam = ids.join(",");

  function runBulk(fn: () => Promise<void>) {
    setError(null);
    startTransition(async () => {
      try {
        await fn();
        clear();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Aktion fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="mb-4 flex flex-col gap-1">
      <div className="flex items-center justify-between rounded-lg border border-neutral-200 bg-neutral-50 px-4 py-2 text-sm">
        <span className="text-neutral-600">{selected.size} ausgewählt</span>
        <div className="flex items-center gap-3">
          {bulkSetVerifiedAction && (
            <button
              type="button"
              disabled={pending}
              onClick={() => runBulk(() => bulkSetVerifiedAction(ids, true))}
              className="rounded-md border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-100 disabled:opacity-50"
            >
              Als geprüft markieren
            </button>
          )}
          {/* Inline statt window.confirm(): Browser unterdrücken wiederholte
           * confirm()-Dialoge nach ein paar Aufrufen automatisch (Chrome/
           * Firefox bieten "Diese Seite daran hindern, weitere Dialoge zu
           * erstellen" an) — jeder weitere Klick tat dann optisch NICHTS,
           * ohne jeden Hinweis, warum (Nutzer-Meldung: Mehrfach-Löschen bei
           * Ensembles reagierte nicht mehr). Gleiches Muster wie ConfirmButton. */}
          {bulkDeleteAction && confirmingDelete && (
            <span className="flex items-center gap-2 text-sm">
              <span className="text-neutral-600">{selected.size} wirklich löschen?</span>
              <button
                type="button"
                disabled={pending}
                onClick={() => {
                  setConfirmingDelete(false);
                  runBulk(() => bulkDeleteAction(ids));
                }}
                className="font-medium text-red-700 hover:text-red-900 disabled:opacity-50"
              >
                {pending ? "…" : "Ja, löschen"}
              </button>
              <button
                type="button"
                disabled={pending}
                onClick={() => setConfirmingDelete(false)}
                className="font-medium text-neutral-500 hover:text-neutral-700 disabled:opacity-50"
              >
                Abbrechen
              </button>
            </span>
          )}
          {bulkDeleteAction && !confirmingDelete && (
            <button
              type="button"
              disabled={pending}
              onClick={() => setConfirmingDelete(true)}
              className="rounded-md border border-red-200 bg-white px-3 py-1.5 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-50"
            >
              Löschen
            </button>
          )}
          <Link
            href={`/bio-research?type=${entityType}&ids=${idsParam}`}
            className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700"
          >
            Bios recherchieren
          </Link>
        </div>
      </div>
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  );
}
