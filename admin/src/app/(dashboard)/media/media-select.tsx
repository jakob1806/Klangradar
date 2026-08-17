"use client";

// Mehrfachauswahl für die Bilder-Lizenz-Review-Queue — Nutzeranfrage:
// "multiauswahl bei dem bilder tab, um 'frei nutzbar' 'lizenziert'
// 'ablehnen' auf mehrere bilder gleichzeitig auszuwählen". Gleiches Muster
// wie bio-select.tsx: EIN Context statt Auswahl-State auf der Server-
// Page zu verwalten.

import { createContext, useContext, useState, useTransition, type ReactNode } from "react";
import { bulkSetLicenseStatus, type LicenseStatus } from "./actions";

interface SelectionContextValue {
  selected: Set<string>;
  toggle: (id: string) => void;
  setAll: (ids: string[], checked: boolean) => void;
  clear: () => void;
}

const SelectionContext = createContext<SelectionContextValue | null>(null);

function useSelection() {
  const ctx = useContext(SelectionContext);
  if (!ctx) throw new Error("useSelection must be used within MediaSelectionProvider");
  return ctx;
}

export function MediaSelectionProvider({ children }: { children: ReactNode }) {
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

  function clear() {
    setSelected(new Set());
  }

  return (
    <SelectionContext.Provider value={{ selected, toggle, setAll, clear }}>{children}</SelectionContext.Provider>
  );
}

export function MediaRowCheckbox({ id }: { id: string }) {
  const { selected, toggle } = useSelection();
  return (
    <input
      type="checkbox"
      className="h-4 w-4 rounded border-neutral-300"
      checked={selected.has(id)}
      onChange={() => toggle(id)}
      aria-label="Auswählen"
      // Klick nicht an den umgebenden Link zur Entität durchreichen.
      onClick={(e) => e.stopPropagation()}
    />
  );
}

/** Die gesamte Bildkarte ist ein komfortables Auswahlziel. Links, Buttons,
 * Formulare und Details innerhalb der Karte behalten ihre eigene Aktion und
 * lösen keine versehentliche Auswahl aus. */
export function MediaSelectableCard({ id, children }: { id: string; children: ReactNode }) {
  const { selected, toggle } = useSelection();
  const isSelected = selected.has(id);

  function isInteractive(target: EventTarget | null) {
    return target instanceof Element && Boolean(target.closest("a, button, input, textarea, select, label, form, details, summary"));
  }

  return (
    <div
      role="checkbox"
      aria-checked={isSelected}
      tabIndex={0}
      onClick={(event) => {
        if (!isInteractive(event.target)) toggle(id);
      }}
      onKeyDown={(event) => {
        if (event.key === " " || event.key === "Enter") {
          event.preventDefault();
          toggle(id);
        }
      }}
      className={`group relative overflow-hidden rounded-2xl border bg-white shadow-sm transition-all focus:outline-none focus-visible:ring-2 focus-visible:ring-[#0071e3] focus-visible:ring-offset-2 ${
        isSelected
          ? "border-[#0071e3] bg-blue-50/30 shadow-md ring-2 ring-[#0071e3]/20"
          : "border-black/[0.07] hover:-translate-y-0.5 hover:border-black/[0.14] hover:shadow-md"
      }`}
    >
      <button
        type="button"
        onClick={(event) => { event.stopPropagation(); toggle(id); }}
        className={`absolute right-3 top-3 z-10 flex h-9 items-center gap-2 rounded-full border px-3 text-xs font-semibold shadow-sm backdrop-blur transition-colors ${
          isSelected
            ? "border-[#0071e3] bg-[#0071e3] text-white"
            : "border-white/70 bg-white/90 text-neutral-700 hover:bg-white"
        }`}
        aria-label={isSelected ? "Auswahl aufheben" : "Bild auswählen"}
      >
        <span className="text-sm">{isSelected ? "✓" : "+"}</span>
        {isSelected ? "Ausgewählt" : "Auswählen"}
      </button>
      {children}
    </div>
  );
}

export function MediaSelectAllCheckbox({ ids }: { ids: string[] }) {
  const { selected, setAll } = useSelection();
  const allSelected = ids.length > 0 && ids.every((id) => selected.has(id));
  return (
    <label className="flex items-center gap-2 text-sm text-neutral-600">
      <input
        type="checkbox"
        className="h-4 w-4 rounded border-neutral-300"
        checked={allSelected}
        onChange={(e) => setAll(ids, e.target.checked)}
        aria-label="Alle auswählen"
      />
      Alle auswählen
    </label>
  );
}

const BULK_LABEL: Record<LicenseStatus, string> = {
  confirmed_free: "Frei nutzbar",
  confirmed_licensed: "Lizenziert",
  rejected: "Ablehnen",
};

const BULK_CONFIRM: Record<LicenseStatus, string> = {
  confirmed_free: "ausgewählte Bilder als frei nutzbar freigeben?",
  confirmed_licensed: "ausgewählte Bilder als lizenziert (mit Quellenangabe) freigeben?",
  rejected: "ausgewählte Bilder ablehnen? Werden nie ausgespielt.",
};

const BULK_CLASS: Record<LicenseStatus, string> = {
  confirmed_free: "border-emerald-200 text-emerald-700 hover:bg-emerald-50",
  confirmed_licensed: "border-amber-200 text-amber-700 hover:bg-amber-50",
  rejected: "border-neutral-300 text-neutral-600 hover:bg-neutral-100",
};

export function MediaBulkBar() {
  const { selected, clear } = useSelection();
  const [pending, startTransition] = useTransition();
  const [confirming, setConfirming] = useState<LicenseStatus | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (selected.size === 0) return null;

  function run(status: LicenseStatus) {
    setError(null);
    const ids = Array.from(selected);
    startTransition(async () => {
      try {
        await bulkSetLicenseStatus(ids, status);
        clear();
        setConfirming(null);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Aktion fehlgeschlagen.");
        setConfirming(null);
      }
    });
  }

  return (
    <div className="sticky top-3 z-20 mb-5 flex flex-col gap-2 rounded-2xl border border-blue-100 bg-white/95 px-4 py-3 shadow-lg backdrop-blur">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="text-sm font-medium text-neutral-700">{selected.size} ausgewählt</span>
        {confirming ? (
          <span className="flex items-center gap-3 text-sm">
            <span className="text-neutral-600">{selected.size} {BULK_CONFIRM[confirming]}</span>
            <button
              type="button"
              disabled={pending}
              onClick={() => run(confirming)}
              className="font-medium text-red-700 hover:text-red-900 disabled:opacity-50"
            >
              {pending ? "…" : "Ja, sicher"}
            </button>
            <button
              type="button"
              disabled={pending}
              onClick={() => setConfirming(null)}
              className="font-medium text-neutral-500 hover:text-neutral-700 disabled:opacity-50"
            >
              Abbrechen
            </button>
          </span>
        ) : (
          <div className="flex flex-wrap items-center gap-2">
            {(["confirmed_free", "confirmed_licensed", "rejected"] as LicenseStatus[]).map((status) => (
              <button
                key={status}
                type="button"
                disabled={pending}
                onClick={() => setConfirming(status)}
                className={`rounded-md border px-3 py-1.5 text-xs font-medium disabled:opacity-50 ${BULK_CLASS[status]}`}
              >
                {BULK_LABEL[status]}
              </button>
            ))}
          </div>
        )}
      </div>
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  );
}
