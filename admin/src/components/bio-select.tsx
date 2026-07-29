"use client";

// Mehrfachauswahl für Personen/Ensembles/Venues-Listen, um mehrere auf
// einmal in den KI-Bio-Recherche-Workflow zu schicken (Nutzeranfrage: "füge
// hinzu, dass man mehrere jeweils auswählen kann und dann mithilfe von KI
// nach einer Bio suchen kann"). Bewusst EIN generischer Baustein statt drei
// fast identischer Kopien für Personen/Ensembles/Venues — nur `entityType`
// unterscheidet sich, der Rest (Auswahl-State, Bulk-Bar, Navigation zum
// Workflow) ist identisch.

import Link from "next/link";
import { createContext, useContext, useState, type ReactNode } from "react";

type EntityType = "person" | "ensemble" | "venue";

interface SelectionContextValue {
  selected: Set<string>;
  toggle: (id: string) => void;
  setAll: (ids: string[], checked: boolean) => void;
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

  return (
    <SelectionContext.Provider value={{ selected, toggle, setAll }}>{children}</SelectionContext.Provider>
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

export function BioResearchBar({ entityType }: { entityType: EntityType }) {
  const { selected } = useSelection();
  if (selected.size === 0) return null;

  const ids = Array.from(selected).join(",");
  return (
    <div className="mb-4 flex items-center justify-between rounded-lg border border-neutral-200 bg-neutral-50 px-4 py-2 text-sm">
      <span className="text-neutral-600">{selected.size} ausgewählt</span>
      <Link
        href={`/bio-research?type=${entityType}&ids=${ids}`}
        className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700"
      >
        Bios recherchieren
      </Link>
    </div>
  );
}
