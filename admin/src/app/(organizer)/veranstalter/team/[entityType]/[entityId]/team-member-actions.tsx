"use client";

import { ConfirmButton } from "@/components/confirm-button";
import { approveTeamClaim, rejectTeamClaim, setTeamMemberRole } from "./actions";
import { useState, useTransition } from "react";
import { Button } from "@/components/organizer/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/organizer/ui/select";

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
          className="text-sm font-medium text-[#175f3c] hover:text-[#0f4a2d] disabled:opacity-50"
        />
        <ConfirmButton
          action={() => rejectTeamClaim(claimId)}
          confirmMessage="Anfrage ablehnen?"
          label="Ablehnen"
          pendingLabel="Lehne ab…"
          className="text-sm font-medium text-[#a91551] hover:text-[#7a1929] disabled:opacity-50"
        />
      </div>
    );
  }

  if (status === "approved") {
    return (
      <div className="flex items-center justify-end gap-3">
        <Select value={selectedRole} onValueChange={(value) => setSelectedRole(value as typeof selectedRole)}>
          <SelectTrigger aria-label="Rolle" className="h-8 w-auto min-w-[9rem] text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="owner">Admin / Owner</SelectItem>
            <SelectItem value="editor">Redaktion</SelectItem>
            <SelectItem value="marketing">Marketing</SelectItem>
            <SelectItem value="finance">Finanzen</SelectItem>
          </SelectContent>
        </Select>
        <Button
          type="button"
          size="sm"
          variant="link"
          disabled={isPending || selectedRole === role}
          onClick={() => startTransition(() => setTeamMemberRole(claimId, selectedRole))}
        >
          {isPending ? "Speichere…" : "Speichern"}
        </Button>
        <ConfirmButton
          action={() => rejectTeamClaim(claimId)}
          confirmMessage="Zugriff entziehen?"
          label="Entfernen"
          pendingLabel="Entferne…"
          className="text-sm font-medium text-[#a91551] hover:text-[#7a1929] disabled:opacity-50"
        />
      </div>
    );
  }

  return null;
}
