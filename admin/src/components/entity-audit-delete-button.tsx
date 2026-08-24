"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { deleteEntityFromAudit, type AuditableEntityType } from "@/lib/entity-audit-actions";

export function EntityAuditDeleteButton({
  entityType,
  entityId,
  flagId,
  displayName,
}: {
  entityType: AuditableEntityType;
  entityId: string;
  flagId: string;
  displayName: string;
}) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (!confirming) {
    return (
      <button
        type="button"
        onClick={() => setConfirming(true)}
        className="mt-3 text-xs font-medium text-red-600 hover:text-red-800"
      >
        Aus Datenbank löschen
      </button>
    );
  }

  return (
    <div className="mt-3 rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-900">
      <p>
        „{displayName}“ endgültig löschen? Verknüpfungen werden vorher sicher gelöst. Diese Aktion kann nicht rückgängig gemacht werden.
      </p>
      <div className="mt-2 flex gap-3">
        <button
          type="button"
          disabled={pending}
          className="font-semibold text-red-700 disabled:opacity-50"
          onClick={() => startTransition(async () => {
            setError(null);
            try {
              await deleteEntityFromAudit(entityType, entityId, flagId);
              router.refresh();
            } catch (cause) {
              setError(cause instanceof Error ? cause.message : "Löschen fehlgeschlagen.");
            }
          })}
        >
          {pending ? "Wird gelöscht…" : "Endgültig löschen"}
        </button>
        <button type="button" disabled={pending} onClick={() => setConfirming(false)} className="text-neutral-600">
          Abbrechen
        </button>
      </div>
      {error && <p className="mt-2 font-medium text-red-700">{error}</p>}
    </div>
  );
}
