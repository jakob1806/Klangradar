"use client";

import { useState } from "react";
import { ConfirmButton } from "@/components/confirm-button";
import { approveEntityEditSuggestion, rejectEntityEditSuggestion } from "./actions";
import type { ClaimableEntityType } from "@/lib/entity-tables";

const ENTITY_TYPE_LABEL: Record<ClaimableEntityType, string> = {
  organizer: "Institution",
  venue: "Venue",
  person: "Person",
  ensemble: "Ensemble",
};

export interface UiFieldChange {
  field: string;
  label: string;
  oldValue: string;
  newValue: string;
}

export interface UiSuggestion {
  id: string;
  entityType: ClaimableEntityType;
  entityName: string;
  requesterLabel: string;
  createdAt: string;
  changes: UiFieldChange[];
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export function SuggestionList({ suggestions }: { suggestions: UiSuggestion[] }) {
  const [hidden, setHidden] = useState<Set<string>>(new Set());
  const visible = suggestions.filter((s) => !hidden.has(s.id));

  if (visible.length === 0) {
    return <p className="text-sm text-neutral-400">Keine offenen Profiländerungsvorschläge.</p>;
  }

  return (
    <div className="flex flex-col gap-4">
      {visible.map((suggestion) => {
        const resolve = () => setHidden((s) => new Set(s).add(suggestion.id));
        return (
          <div key={suggestion.id} className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
            <div className="flex items-start justify-between gap-4 border-b border-black/[0.06] px-4 py-3">
              <div>
                <p className="font-medium text-neutral-900">
                  {suggestion.entityName}{" "}
                  <span className="font-normal text-neutral-500">({ENTITY_TYPE_LABEL[suggestion.entityType]})</span>
                </p>
                <p className="text-xs text-neutral-500">
                  Vorgeschlagen von {suggestion.requesterLabel} · {formatDate(suggestion.createdAt)}
                </p>
              </div>
              <div className="flex items-center gap-3">
                <ConfirmButton
                  action={async () => {
                    await approveEntityEditSuggestion(suggestion.id);
                    resolve();
                  }}
                  confirmMessage="Änderung übernehmen?"
                  label="Genehmigen"
                  pendingLabel="Genehmige…"
                  className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
                />
                <ConfirmButton
                  action={async () => {
                    await rejectEntityEditSuggestion(suggestion.id);
                    resolve();
                  }}
                  confirmMessage="Vorschlag ablehnen?"
                  label="Ablehnen"
                  pendingLabel="Lehne ab…"
                  className="text-sm font-medium text-red-700 hover:text-red-900 disabled:opacity-50"
                />
              </div>
            </div>
            <table className="w-full text-sm">
              <tbody className="divide-y divide-neutral-100">
                {suggestion.changes.map((change) => (
                  <tr key={change.field}>
                    <td className="w-40 px-4 py-2 text-neutral-500">{change.label}</td>
                    <td className="px-4 py-2 text-neutral-400 line-through">{change.oldValue || "—"}</td>
                    <td className="px-4 py-2 font-medium text-neutral-900">{change.newValue || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      })}
    </div>
  );
}
