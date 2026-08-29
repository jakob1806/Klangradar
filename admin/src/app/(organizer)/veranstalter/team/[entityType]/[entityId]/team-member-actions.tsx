"use client";

import { ConfirmButton } from "@/components/confirm-button";
import { approveTeamClaim, rejectTeamClaim, setTeamMemberRole } from "./actions";
import { useState, useTransition } from "react";

// Owner-only Aktionen pro Zeile — die Seite rendert diese Komponente nur,
// wenn der aktuelle Nutzer Owner ist; RLS ("Owner verwaltet Team-Claims der
// eigenen Entität") ist trotzdem die eigentliche Durchsetzung, hier geht es
// nur um die UI-Sichtbarkeit.
export function TeamMemberActions({
  claimId,
  status,
  role,
}: {
  claimId: string;
  status: "pending" | "approved" | "rejected";
  role: "owner" | "editor" | "marketing" | "finance";
}) {
  const [selectedRole, setSelectedRole] = useState(role);
  const [isPending, startTransition] = useTransition();
  if (status === "pending") {
    return (
      <div className="flex items-center justify-end gap-3">
        <ConfirmButton
          action={() => approveTeamClaim(claimId)}
          confirmMessage="Zugriff gewähren?"
          label="Genehmigen"
          pendingLabel="Genehmige…"
          className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
        />
        <ConfirmButton
          action={() => rejectTeamClaim(claimId)}
          confirmMessage="Anfrage ablehnen?"
          label="Ablehnen"
          pendingLabel="Lehne ab…"
          className="text-sm font-medium text-red-700 hover:text-red-900 disabled:opacity-50"
        />
      </div>
    );
  }

  if (status === "approved") {
    return (
      <div className="flex items-center justify-end gap-3">
        <select aria-label="Rolle" value={selectedRole} onChange={(event) => setSelectedRole(event.target.value as typeof selectedRole)} className="rounded-lg border border-black/[.12] bg-white px-2 py-1 text-xs text-[#48484a]"><option value="owner">Admin / Owner</option><option value="editor">Redaktion</option><option value="marketing">Marketing</option><option value="finance">Finanzen</option></select>
        <button type="button" disabled={isPending || selectedRole === role} onClick={() => startTransition(() => setTeamMemberRole(claimId, selectedRole))} className="text-sm font-medium text-[#0071e3] hover:underline disabled:opacity-50">{isPending ? "Speichere…" : "Speichern"}</button>
        <ConfirmButton
          action={() => rejectTeamClaim(claimId)}
          confirmMessage="Zugriff entziehen?"
          label="Entfernen"
          pendingLabel="Entferne…"
          className="text-sm font-medium text-red-700 hover:text-red-900 disabled:opacity-50"
        />
      </div>
    );
  }

  return null;
}
