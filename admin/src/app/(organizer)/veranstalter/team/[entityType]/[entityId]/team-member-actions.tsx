"use client";

import { ConfirmButton } from "@/components/confirm-button";
import { approveTeamClaim, rejectTeamClaim, setTeamMemberRole } from "./actions";

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
  role: "owner" | "editor";
}) {
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
        <ConfirmButton
          action={() => setTeamMemberRole(claimId, role === "owner" ? "editor" : "owner")}
          confirmMessage={role === "owner" ? "Zu Editor herabstufen?" : "Zu Owner befördern?"}
          label={role === "owner" ? "Zu Editor machen" : "Zu Owner machen"}
          pendingLabel="Speichere…"
          className="text-sm font-medium text-[#0071e3] hover:underline disabled:opacity-50"
        />
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
