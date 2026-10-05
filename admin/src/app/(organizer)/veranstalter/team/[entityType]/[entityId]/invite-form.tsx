"use client";

import { useState, useTransition } from "react";
import { Mail } from "lucide-react";
import { Button } from "@/components/organizer/ui/button";
import { Input } from "@/components/organizer/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/organizer/ui/select";
import { INVITE_ROLE_DESCRIPTION, INVITE_ROLE_LABEL } from "@/lib/team-invitation";
import { inviteTeamMember, resendTeamInvitation, revokeTeamInvitation } from "./invite-actions";

const ROLES = ["editor", "marketing", "finance", "owner"] as const;

export function InviteForm({ entityType, entityId }: { entityType: string; entityId: string }) {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<(typeof ROLES)[number]>("editor");
  const [feedback, setFeedback] = useState<{ ok: boolean; text: string } | null>(null);
  const [isPending, startTransition] = useTransition();

  function submit(event: React.FormEvent) {
    event.preventDefault();
    setFeedback(null);
    startTransition(async () => {
      const result = await inviteTeamMember(entityType, entityId, email, role);
      if (result.ok) {
        setFeedback({ ok: true, text: result.message });
        setEmail("");
      } else {
        setFeedback({ ok: false, text: result.error });
      }
    });
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-3 rounded-2xl border border-[#15131a]/[0.07] bg-white p-5">
      <div className="flex flex-col gap-1">
        <h2 className="text-[15px] font-bold text-[#18181B]">Mitglied einladen</h2>
        <p className="text-[13px] text-[#726c78]">
          Die Person erhält eine E-Mail mit einem Link und kann die Einladung auf einer eigenen Seite annehmen oder ablehnen.
        </p>
      </div>
      <div className="flex flex-col gap-3 sm:flex-row">
        <Input
          type="email"
          required
          placeholder="name@beispiel.de"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="flex-1"
          aria-label="E-Mail-Adresse"
        />
        <Select value={role} onValueChange={(value) => setRole(value as (typeof ROLES)[number])}>
          <SelectTrigger className="sm:w-52" aria-label="Rolle">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {ROLES.map((r) => (
              <SelectItem key={r} value={r}>
                {INVITE_ROLE_LABEL[r]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button type="submit" disabled={isPending || email.trim() === ""}>
          <Mail /> {isPending ? "Sende…" : "Einladung senden"}
        </Button>
      </div>
      <p className="text-[12px] text-[#A1A1AA]">{INVITE_ROLE_DESCRIPTION[role]}</p>
      {feedback && (
        <p className={`text-sm ${feedback.ok ? "text-[#175f3c]" : "text-[#a91551]"}`} role="status">
          {feedback.text}
        </p>
      )}
    </form>
  );
}

export function InvitationRowActions({ invitationId }: { invitationId: string }) {
  const [note, setNote] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  return (
    <div className="flex items-center justify-end gap-3">
      {note && <span className="text-xs text-[#726c78]">{note}</span>}
      <button
        disabled={isPending}
        className="text-sm font-medium text-[#2D2A6E] hover:underline disabled:opacity-50"
        onClick={() =>
          startTransition(async () => {
            const r = await resendTeamInvitation(invitationId);
            setNote(r.ok ? "Erneut gesendet" : r.error);
          })
        }
      >
        Erneut senden
      </button>
      <button
        disabled={isPending}
        className="text-sm font-medium text-[#a91551] hover:text-[#7a1929] disabled:opacity-50"
        onClick={() =>
          startTransition(async () => {
            await revokeTeamInvitation(invitationId);
          })
        }
      >
        Zurückziehen
      </button>
    </div>
  );
}
