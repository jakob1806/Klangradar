"use client";

import { useState } from "react";
import { ConfirmButton } from "@/components/confirm-button";
import { approveEntityClaim, rejectEntityClaim } from "./actions";
import type { ClaimableEntityType } from "@/lib/entity-tables";

const ENTITY_TYPE_LABEL: Record<ClaimableEntityType, string> = {
  organizer: "Institution",
  venue: "Venue",
  person: "Person",
  ensemble: "Ensemble",
};

export interface UiClaim {
  id: string;
  entityType: ClaimableEntityType;
  entityName: string;
  requesterLabel: string;
  justification: string | null;
  verificationEmail: string | null;
  evidenceUrl: string | null;
  createdAt: string;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export function ClaimList({ claims }: { claims: UiClaim[] }) {
  const [hidden, setHidden] = useState<Set<string>>(new Set());
  const visible = claims.filter((c) => !hidden.has(c.id));

  if (visible.length === 0) {
    return <p className="text-sm text-neutral-400">Keine offenen Claim-Anfragen.</p>;
  }

  return (
    <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
      <table className="w-full text-sm">
        <thead className="border-b border-black/[0.06] text-left">
          <tr>
            <th className="type-label px-4 py-3">Entität</th>
            <th className="type-label px-4 py-3">Typ</th>
            <th className="type-label px-4 py-3">Antragsteller</th>
            <th className="type-label px-4 py-3">Begründung</th>
            <th className="type-label px-4 py-3">Nachweis</th>
            <th className="type-label px-4 py-3">Angefragt</th>
            <th className="px-4 py-3" />
          </tr>
        </thead>
        <tbody className="divide-y divide-neutral-200">
          {visible.map((claim) => {
            const resolve = () => setHidden((s) => new Set(s).add(claim.id));
            return (
              <tr key={claim.id} className="hover:bg-neutral-50">
                <td className="px-4 py-3 font-medium text-neutral-900">{claim.entityName}</td>
                <td className="px-4 py-3 text-neutral-600">{ENTITY_TYPE_LABEL[claim.entityType]}</td>
                <td className="px-4 py-3 text-neutral-600">{claim.requesterLabel}</td>
                <td className="max-w-xs truncate px-4 py-3 text-neutral-500" title={claim.justification ?? undefined}>
                  {claim.justification ?? "—"}
                </td>
                <td className="px-4 py-3 text-neutral-600">
                  {claim.verificationEmail && <p>{claim.verificationEmail}</p>}
                  {claim.evidenceUrl && <a href={claim.evidenceUrl} target="_blank" rel="noreferrer" className="text-[#0071e3] hover:underline">Nachweis öffnen ↗</a>}
                </td>
                <td className="px-4 py-3 tabular-nums text-neutral-500">{formatDate(claim.createdAt)}</td>
                <td className="px-4 py-3">
                  <div className="flex items-center justify-end gap-3">
                    <ConfirmButton
                      action={async () => {
                        await approveEntityClaim(claim.id);
                        resolve();
                      }}
                      confirmMessage="Zugriff gewähren?"
                      label="Genehmigen"
                      pendingLabel="Genehmige…"
                      className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
                    />
                    <ConfirmButton
                      action={async () => {
                        await rejectEntityClaim(claim.id);
                        resolve();
                      }}
                      confirmMessage="Anfrage ablehnen?"
                      label="Ablehnen"
                      pendingLabel="Lehne ab…"
                      className="text-sm font-medium text-red-700 hover:text-red-900 disabled:opacity-50"
                    />
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
