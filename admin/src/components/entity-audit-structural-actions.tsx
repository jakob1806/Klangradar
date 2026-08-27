"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState, useTransition } from "react";
import {
  repairMisclassifiedEnsemble,
  type EnsembleStructuralRepair,
} from "@/lib/entity-audit-actions";

type Issue = { id: string; message: string };

function splitPersonNames(displayName: string): string[] {
  return displayName
    .replace(/[*_`]/g, "")
    .split(/\s*(?:,|;|\s+und\s+)\s*/i)
    .map((name) => name.trim())
    .filter((name) => name.split(/\s+/).length >= 2);
}

export function EntityAuditStructuralActions({
  entityType,
  entityId,
  flagId,
  displayName,
  issues,
}: {
  entityType: string;
  entityId: string;
  flagId: string;
  displayName: string;
  issues: Issue[];
}) {
  const router = useRouter();
  const [confirming, setConfirming] = useState<EnsembleStructuralRepair | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const names = useMemo(() => splitPersonNames(displayName), [displayName]);
  if (entityType !== "ensemble") return null;

  const evidence = issues.map((issue) => `${issue.id} ${issue.message}`).join(" ").toLocaleLowerCase("de");
  const isMultiplePeople = /mehrere person|zwei person|personennamen/.test(evidence) && names.length >= 2;
  const isOrganizer = /institution|veranstalter|agentur|stiftung|rundfunk|opernhaus|theaterbetrieb|produktionsfirma|konzertdirektion/.test(evidence);
  const isPerson = !isMultiplePeople && !isOrganizer && /personenname|einzelperson|als person|person statt ensemble/.test(evidence);
  const actions: Array<{ repair: EnsembleStructuralRepair; label: string; description: string }> = [];
  if (isPerson) actions.push({
    repair: "person",
    label: "Als Person korrigieren",
    description: "Die Event-Verknüpfungen und vorhandenen Daten werden zur Person verschoben.",
  });
  if (isMultiplePeople) actions.push({
    repair: "people",
    label: `In ${names.length} Personen aufteilen`,
    description: `Erstellt/verknüpft ${names.join(" und ")} einzeln und entfernt den kombinierten Eintrag.`,
  });
  if (isOrganizer) actions.push({
    repair: "organizer",
    label: "Als Veranstalter korrigieren",
    description: "Die Institution wird zu den Veranstaltern verschoben und aus Mitwirkenden entfernt.",
  });
  if (actions.length === 0) return null;

  const selected = actions.find((action) => action.repair === confirming);
  return (
    <div className="mt-3 rounded-xl border border-blue-200 bg-blue-50/70 p-3 text-xs text-blue-950">
      <p className="font-semibold">Strukturelle Korrektur</p>
      {!selected ? (
        <div className="mt-2 flex flex-wrap gap-2">
          {actions.map((action) => (
            <button
              key={action.repair}
              type="button"
              onClick={() => setConfirming(action.repair)}
              className="rounded-lg bg-[#0071e3] px-3 py-2 font-semibold text-white hover:bg-[#0068d1]"
            >
              {action.label}
            </button>
          ))}
        </div>
      ) : (
        <div className="mt-2">
          <p>{selected.description}</p>
          <div className="mt-2 flex gap-3">
            <button
              type="button"
              disabled={pending}
              className="font-semibold text-blue-700 disabled:opacity-50"
              onClick={() => startTransition(async () => {
                setError(null);
                try {
                  await repairMisclassifiedEnsemble(entityId, flagId, selected.repair, names);
                  router.refresh();
                } catch (cause) {
                  setError(cause instanceof Error ? cause.message : "Korrektur fehlgeschlagen.");
                }
              })}
            >
              {pending ? "Wird korrigiert…" : "Korrektur ausführen"}
            </button>
            <button type="button" disabled={pending} onClick={() => setConfirming(null)} className="text-neutral-600">
              Abbrechen
            </button>
          </div>
        </div>
      )}
      {error && <p className="mt-2 font-medium text-red-700">{error}</p>}
    </div>
  );
}
