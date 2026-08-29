"use client";

import { useTransition, useState } from "react";
import { ConfirmButton } from "@/components/confirm-button";
import { setTrustLevel, clearTrustLevel } from "./actions";
import type { ClaimableEntityType, TrustLevel } from "@/lib/entity-tables";

const ENTITY_TYPE_LABEL: Record<ClaimableEntityType, string> = {
  organizer: "Institution",
  venue: "Venue",
  person: "Person",
  ensemble: "Ensemble",
};

const TRUST_LABEL: Record<TrustLevel, string> = {
  unverified: "Unbestätigt",
  claimed: "Beansprucht",
  verified: "Verifiziert",
  official: "Offiziell",
};

export interface UiTrustEntity {
  entityType: ClaimableEntityType;
  entityId: string;
  entityName: string;
  level: TrustLevel;
}

export function TrustList({ entities }: { entities: UiTrustEntity[] }) {
  if (entities.length === 0) {
    return <p className="text-sm text-neutral-400">Keine beanspruchten Entitäten.</p>;
  }

  return (
    <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
      <table className="w-full text-sm">
        <thead className="border-b border-black/[0.06] text-left">
          <tr>
            <th className="type-label px-4 py-3">Entität</th>
            <th className="type-label px-4 py-3">Typ</th>
            <th className="type-label px-4 py-3">Stufe</th>
            <th className="px-4 py-3" />
          </tr>
        </thead>
        <tbody className="divide-y divide-neutral-200">
          {entities.map((entity) => (
            <TrustRow key={`${entity.entityType}:${entity.entityId}`} entity={entity} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function TrustRow({ entity }: { entity: UiTrustEntity }) {
  const [level, setLevel] = useState(entity.level);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function run(action: () => Promise<void>, optimistic: TrustLevel) {
    setError(null);
    const previous = level;
    setLevel(optimistic);
    startTransition(async () => {
      try {
        await action();
      } catch (err) {
        setLevel(previous);
        setError(err instanceof Error ? err.message : "Aktion fehlgeschlagen.");
      }
    });
  }

  return (
    <tr className="hover:bg-neutral-50">
      <td className="px-4 py-3 font-medium text-neutral-900">{entity.entityName}</td>
      <td className="px-4 py-3 text-neutral-600">{ENTITY_TYPE_LABEL[entity.entityType]}</td>
      <td className="px-4 py-3">
        <span className="type-label rounded-full border border-black/10 bg-black/[0.03] px-2.5 py-1 !text-neutral-700">
          {TRUST_LABEL[level]}
        </span>
      </td>
      <td className="px-4 py-3">
        <div className="flex items-center justify-end gap-3">
          {level !== "verified" && (
            <button
              type="button"
              disabled={pending}
              onClick={() => run(() => setTrustLevel(entity.entityType, entity.entityId, "verified"), "verified")}
              className="text-sm font-medium text-[#0071e3] hover:underline disabled:opacity-50"
            >
              Verifizieren
            </button>
          )}
          {level !== "official" && (
            <button
              type="button"
              disabled={pending}
              onClick={() => run(() => setTrustLevel(entity.entityType, entity.entityId, "official"), "official")}
              className="text-sm font-medium text-[#0071e3] hover:underline disabled:opacity-50"
            >
              Als offiziell markieren
            </button>
          )}
          {(level === "verified" || level === "official") && (
            <ConfirmButton
              action={async () => {
                await clearTrustLevel(entity.entityType, entity.entityId);
                setLevel("claimed");
              }}
              confirmMessage="Stufe zurücksetzen?"
              label="Zurücksetzen"
              pendingLabel="Setze zurück…"
              className="text-sm font-medium text-neutral-500 hover:text-neutral-700 disabled:opacity-50"
            />
          )}
        </div>
        {error && <p className="mt-1 text-right text-xs text-red-600">{error}</p>}
      </td>
    </tr>
  );
}
