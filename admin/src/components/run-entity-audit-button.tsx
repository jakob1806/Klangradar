"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import {
  type AuditableEntityType,
  finishEntityAudit,
  runEntityAuditPage,
} from "@/lib/entity-audit-actions";

const LABEL: Record<AuditableEntityType, string> = {
  person: "Alle Personen prüfen",
  ensemble: "Alle Ensembles prüfen",
  venue: "Alle Venues prüfen",
  work: "Alle Werke prüfen",
  event: "Alle Veranstaltungen prüfen",
};

const PENDING_LABEL: Record<AuditableEntityType, string> = {
  person: "Prüft alle Personen…",
  ensemble: "Prüft alle Ensembles…",
  venue: "Prüft alle Venues…",
  work: "Prüft alle Werke…",
  event: "Prüft alle Veranstaltungen…",
};

export function RunEntityAuditButton({ entityType }: { entityType: AuditableEntityType }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [summary, setSummary] = useState<string | null>(null);
  const [progress, setProgress] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    setSummary(null);
    startTransition(async () => {
      let offset = 0;
      let totalChecked = 0;
      let totalFlagged = 0;
      let aiUsed = false;
      let aiFailures = 0;
      try {
        for (;;) {
          const page = await runEntityAuditPage(entityType, offset);
          totalChecked += page.checkedInPage;
          totalFlagged += page.flaggedInPage;
          aiUsed = aiUsed || page.aiUsed;
          aiFailures += page.aiFailures;
          setProgress(`${Math.min(totalChecked, page.totalCount)} / ${page.totalCount} geprüft…`);
          offset += page.checkedInPage;
          if (page.done || page.checkedInPage === 0) break;
        }
        await finishEntityAudit();
        setSummary(
          `${totalChecked} geprüft, ${totalFlagged} mit Auffälligkeiten` +
            (aiUsed ? "" : " (ohne KI-Prüfung — kein AI-Provider konfiguriert)") +
            (aiFailures > 0 ? ` · ${aiFailures} KI-Batches fehlgeschlagen` : ""),
        );
        setProgress(null);
        router.refresh();
      } catch (auditError) {
        setError(auditError instanceof Error ? auditError.message : "Die Prüfung ist fehlgeschlagen.");
        setProgress(null);
      }
    });
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="rounded-lg border border-violet-200 bg-violet-50 px-3 py-1.5 text-[13px] font-medium text-violet-900 transition-colors hover:bg-violet-100 disabled:cursor-wait disabled:opacity-60"
      >
        {pending ? PENDING_LABEL[entityType] : LABEL[entityType]}
      </button>
      {progress && <p className="max-w-xs text-right text-xs text-neutral-500">{progress}</p>}
      {error && <p role="alert" className="max-w-xs text-right text-xs text-red-600">{error}</p>}
      {summary && <p className="max-w-xs text-right text-xs text-neutral-500">{summary}</p>}
    </div>
  );
}
