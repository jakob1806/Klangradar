"use client";

// Nutzeranfrage: "mehrfachauswahl bei der review queue, um schneller
// kandidaten hinzuzufügen oder zu löschen" — bezogen auf die Low-
// Confidence-Events-Tabelle hier (die einzige Liste auf dieser Seite mit
// tatsächlichen Zeilen; die drei Kategorien darüber sind nur Zähler-Links
// zu ihren jeweils eigenen, bereits mit Mehrfachauswahl ausgestatteten
// Seiten — entity-candidates, duplicates).

import Link from "next/link";
import { useState, useTransition } from "react";
import { bulkClearReview, bulkRejectReview } from "./actions";

export interface LowConfidenceEvent {
  id: string;
  title: string;
  start_datetime: string;
  status: string;
  import_confidence: number;
  venueName: string | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { dateStyle: "medium", timeStyle: "short" });
}

export function LowConfidenceTable({ events }: { events: LowConfidenceEvent[] }) {
  const [dismissed, setDismissed] = useState<Set<string>>(new Set());
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);

  const visible = events.filter((e) => !dismissed.has(e.id));
  const allSelected = visible.length > 0 && visible.every((e) => selected.has(e.id));

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleAll(checked: boolean) {
    setSelected(checked ? new Set(visible.map((e) => e.id)) : new Set());
  }

  function runBulk(action: "clear" | "reject") {
    const ids = Array.from(selected);
    if (ids.length === 0) return;
    setMessage(null);
    startTransition(async () => {
      const result = action === "clear" ? await bulkClearReview(ids) : await bulkRejectReview(ids);
      if (result.error) {
        setMessage(`Fehler: ${result.error}`);
      } else {
        ids.forEach((id) => dismissed.add(id));
        setDismissed(new Set(dismissed));
        setSelected(new Set());
        setMessage(
          `${result.updated} Event(s) ${action === "clear" ? "als geprüft markiert" : "abgelehnt (auf Entwurf gesetzt)"}.`,
        );
      }
    });
  }

  return (
    <div>
      {selected.size > 0 && (
        <div className="mb-3 flex items-center justify-between border-2 border-[#171717] bg-neutral-50 px-4 py-2 text-sm">
          <span className="text-neutral-600">{selected.size} ausgewählt</span>
          <div className="flex items-center gap-3">
            <button
              type="button"
              disabled={pending}
              onClick={() => runBulk("reject")}
              className="border border-neutral-300 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-white disabled:opacity-50"
            >
              Ablehnen (auf Entwurf setzen)
            </button>
            <button
              type="button"
              disabled={pending}
              onClick={() => runBulk("clear")}
              className="border-2 border-[#171717] bg-[#171717] px-3 py-1.5 text-sm font-medium text-white hover:bg-white hover:text-[#171717] disabled:opacity-50"
            >
              Als geprüft markieren
            </button>
          </div>
        </div>
      )}
      {message && <p className="mb-3 text-xs text-neutral-500">{message}</p>}

      <div className="overflow-hidden border-2 border-[#171717] bg-white">
        <table className="w-full text-sm">
          <thead className="border-b-2 border-[#171717] text-left">
            <tr>
              <th className="w-10 px-4 py-3">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-neutral-300"
                  checked={allSelected}
                  onChange={(e) => toggleAll(e.target.checked)}
                  aria-label="Alle auswählen"
                />
              </th>
              <th className="type-label px-4 py-3">Titel</th>
              <th className="type-label px-4 py-3">Venue</th>
              <th className="type-label px-4 py-3">Termin</th>
              <th className="type-label px-4 py-3">Status</th>
              <th className="type-label px-4 py-3">Score</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-200">
            {visible.length ? (
              visible.map((e) => (
                <tr key={e.id} className="hover:bg-neutral-50">
                  <td className="px-4 py-3">
                    <input
                      type="checkbox"
                      className="h-4 w-4 rounded border-neutral-300"
                      checked={selected.has(e.id)}
                      onChange={() => toggle(e.id)}
                      aria-label="Auswählen"
                    />
                  </td>
                  <td className="px-4 py-3 font-medium text-neutral-900">{e.title}</td>
                  <td className="px-4 py-3 text-neutral-600">{e.venueName ?? "—"}</td>
                  <td className="px-4 py-3 text-neutral-600">{formatDate(e.start_datetime)}</td>
                  <td className="px-4 py-3 text-neutral-600">{e.status}</td>
                  <td className="px-4 py-3 text-amber-700">{Math.round(e.import_confidence * 100)}%</td>
                  <td className="px-4 py-3 text-right">
                    <Link href={`/events/${e.id}`} className="text-sm font-medium text-neutral-700 hover:text-neutral-900">
                      Prüfen →
                    </Link>
                  </td>
                </tr>
              ))
            ) : (
              <tr>
                <td colSpan={7} className="px-4 py-10 text-center text-neutral-400">
                  Keine Events mit niedrigem Confidence-Score.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
