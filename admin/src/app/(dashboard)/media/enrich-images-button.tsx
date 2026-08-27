"use client";

import { useState, useTransition } from "react";
import { enrichEntityImages, type EnrichImagesResult } from "./actions";

const KIND_LABEL: Record<string, string> = {
  persons: "Personen",
  ensembles: "Ensembles",
};

/** Startet einen gezielten Batch für fehlende Personen- und Ensemblebilder. */
export function EnrichImagesButton() {
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<EnrichImagesResult | null>(null);

  function run() {
    startTransition(async () => {
      setResult(await enrichEntityImages());
    });
  }

  const totalQueued = result?.perKind
    ? Object.values(result.perKind).reduce((sum, r) => sum + r.queuedForReview, 0)
    : 0;
  const totalApplied = result?.perKind
    ? Object.values(result.perKind).reduce((sum, r) => sum + r.autoApplied, 0)
    : 0;
  const allErrors = result?.perKind
    ? Object.values(result.perKind).flatMap((r) => r.errors)
    : [];

  return (
    <div className="flex flex-col items-end gap-2">
      <button
        type="button"
        disabled={pending}
        onClick={run}
        className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
      >
        {pending ? "Personen-/Ensemblebilder werden gesucht…" : "Nächste Personen-/Ensemblebilder automatisch suchen"}
      </button>
      {result?.status === "failed" && (
        <p className="max-w-xs text-right text-xs text-red-600">{result.error}</p>
      )}
      {result?.status === "ok" && (
        <p className="max-w-xs text-right text-xs text-neutral-600">
          {totalApplied} direkt übernommen · {totalQueued} zur Freigabe
          {result.perKind && (
            <>
              {" "}
              (
              {Object.entries(result.perKind)
                .map(([kind, r]) => `${KIND_LABEL[kind] ?? kind}: ${r.autoApplied + r.queuedForReview}/${r.found}`)
                .join(", ")}
              )
            </>
          )}
          {allErrors.length > 0 && (
            <span className="mt-1 block text-amber-700">{allErrors.slice(0, 3).join("; ")}</span>
          )}
        </p>
      )}
    </div>
  );
}
