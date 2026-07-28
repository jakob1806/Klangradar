"use client";

// Mehrfachauswahl für die Events-Tabelle, damit mehrere Entwürfe in einem
// Schritt veröffentlicht werden können (bisher nur einzeln über das
// Bearbeiten-Formular möglich). Reiner Client-State (Context) um die
// Server-gerenderte Tabelle herum — Datumsformatierung/Statuslabels bleiben
// im Server Component, nur die Checkbox-Interaktion ist client-seitig.

import Link from "next/link";
import {
  createContext,
  useContext,
  useState,
  useTransition,
  type ReactNode,
} from "react";
import { bulkPublishEvents, publishEvent } from "./actions";

interface SelectionContextValue {
  selected: Set<string>;
  toggle: (id: string) => void;
  setAll: (ids: string[], checked: boolean) => void;
}

const SelectionContext = createContext<SelectionContextValue | null>(null);

function useSelection() {
  const ctx = useContext(SelectionContext);
  if (!ctx) throw new Error("useSelection must be used within BulkSelectionProvider");
  return ctx;
}

export function BulkSelectionProvider({ children }: { children: ReactNode }) {
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
    <SelectionContext.Provider value={{ selected, toggle, setAll }}>
      {children}
    </SelectionContext.Provider>
  );
}

export function RowCheckbox({ eventId }: { eventId: string }) {
  const { selected, toggle } = useSelection();
  return (
    <input
      type="checkbox"
      className="h-4 w-4 rounded border-neutral-300"
      checked={selected.has(eventId)}
      onChange={() => toggle(eventId)}
      aria-label="Auswählen"
    />
  );
}

/** Ein-Klick-Veröffentlichen für genau einen Entwurf, ohne erst die
 * Checkbox anzuhaken und die Bulk-Bar zu benutzen. Rein lokaler
 * useTransition-Zustand pro Zeile (keine Auswahl-Interaktion mit
 * BulkSelectionProvider nötig). */
export function PublishRowButton({ eventId }: { eventId: string }) {
  const [pending, startTransition] = useTransition();
  const [failed, setFailed] = useState(false);

  function publish() {
    startTransition(async () => {
      const result = await publishEvent(eventId);
      setFailed(Boolean(result.error));
    });
  }

  return (
    <button
      type="button"
      disabled={pending}
      onClick={publish}
      className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
    >
      {pending ? "Wird veröffentlicht…" : failed ? "Fehlgeschlagen — erneut?" : "Veröffentlichen"}
    </button>
  );
}

export function SelectAllCheckbox({ ids }: { ids: string[] }) {
  const { selected, setAll } = useSelection();
  const allSelected = ids.length > 0 && ids.every((id) => selected.has(id));
  return (
    <input
      type="checkbox"
      className="h-4 w-4 rounded border-neutral-300"
      checked={allSelected}
      onChange={(e) => setAll(ids, e.target.checked)}
      aria-label="Alle auf dieser Seite auswählen"
    />
  );
}

/** Erscheint nur, wenn mindestens ein Event ausgewählt ist. Setzt beim Klick
 * alle ausgewählten Entwürfe auf status='scheduled' (die Server Action
 * ignoriert dabei alles, was nicht aktuell 'draft' ist — ein versehentliches
 * "Alle"-Tab-Markieren kann so keine bereits abgesagten/verschobenen Events
 * zurücksetzen). */
export function BulkActionBar() {
  const { selected, setAll } = useSelection();
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);

  if (selected.size === 0 && !message) return null;

  function publish() {
    const ids = Array.from(selected);
    startTransition(async () => {
      const result = await bulkPublishEvents(ids);
      if (result.error) {
        setMessage(`Fehler: ${result.error}`);
      } else {
        setMessage(`${result.updated} Entwurf/Entwürfe veröffentlicht.`);
        setAll(ids, false);
      }
    });
  }

  return (
    <div className="mb-4 flex items-center justify-between rounded-lg border border-neutral-200 bg-neutral-50 px-4 py-2 text-sm">
      <span className="text-neutral-600">
        {message ?? `${selected.size} ausgewählt`}
      </span>
      {selected.size > 0 && (
        <div className="flex items-center gap-3">
          <Link
            href={`/events/bulk-edit?ids=${Array.from(selected).join(",")}`}
            className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-white"
          >
            Bearbeiten
          </Link>
          <button
            type="button"
            disabled={pending}
            onClick={publish}
            className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
          >
            {pending ? "Wird veröffentlicht…" : "Veröffentlichen"}
          </button>
        </div>
      )}
    </div>
  );
}
