"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import {
  auditEntity,
  type AuditEntityType,
  type AuditIssue,
  type AuditResult,
} from "@/lib/audit-actions";

const CATEGORY_LABEL: Record<AuditIssue["category"], string> = {
  duplicate: "Mögliches Duplikat",
  name: "Name",
  spelling: "Schreibweise",
  completeness: "Vollständigkeit",
  contradiction: "Widerspruch",
  plausibility: "Plausibilität",
};

const SEVERITY_STYLE: Record<AuditIssue["severity"], string> = {
  critical: "border-red-200 bg-red-50 text-red-800",
  warning: "border-amber-200 bg-amber-50 text-amber-900",
  info: "border-blue-200 bg-blue-50 text-blue-800",
};

const ENTITY_PATH: Record<AuditEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  venue: "venues",
  event: "events",
};

function ResultPanel({ entityType, result }: { entityType: AuditEntityType; result: AuditResult }) {
  if (result.status === "clean") {
    return (
      <div className="max-w-2xl rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-900">
        <p className="font-semibold">Keine konkrete Unstimmigkeit gefunden</p>
        <p className="mt-1">{result.summary}</p>
        <p className="mt-2 text-xs text-green-800/80">Es wurden keine Daten verändert.</p>
      </div>
    );
  }

  return (
    <div className="w-full max-w-2xl rounded-lg border border-amber-200 bg-amber-50/40 p-4 text-sm text-neutral-900">
      <p className="font-semibold">{result.issues.length} Auffälligkeit{result.issues.length === 1 ? "" : "en"} gefunden</p>
      <p className="mt-1 text-neutral-700">{result.summary}</p>
      <ul className="mt-3 space-y-2">
        {result.issues.map((issue) => (
          <li key={issue.id} className={`rounded-md border px-3 py-2 ${SEVERITY_STYLE[issue.severity]}`}>
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
              <span className="text-[11px] font-semibold uppercase tracking-wide">
                {CATEGORY_LABEL[issue.category]}
              </span>
              <span className="text-[11px] opacity-70">{issue.source === "ai" ? "KI-Hinweis" : "Regelprüfung"}</span>
            </div>
            <p className="mt-1 font-medium">{issue.message}</p>
            {issue.suggestion && <p className="mt-1 text-xs opacity-90">Vorschlag: {issue.suggestion}</p>}
            {issue.relatedId && (
              <Link
                href={`/${ENTITY_PATH[entityType]}/${issue.relatedId}`}
                className="mt-2 inline-flex text-xs font-semibold underline underline-offset-2"
              >
                Vergleichseintrag „{issue.relatedName ?? issue.relatedId}“ öffnen →
              </Link>
            )}
          </li>
        ))}
      </ul>
      <p className="mt-3 text-xs text-neutral-500">
        Die Hinweise sind eine redaktionelle Vorprüfung. Es wurden keine Daten automatisch verändert.
      </p>
    </div>
  );
}

export function EntityAuditButton({ entityType, entityId }: { entityType: AuditEntityType; entityId: string }) {
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<AuditResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setResult(null);
    setError(null);
    startTransition(async () => {
      try {
        setResult(await auditEntity(entityType, entityId));
      } catch (auditError) {
        setError(auditError instanceof Error ? auditError.message : "Die KI-Prüfung ist fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="flex w-full flex-col items-start gap-2 sm:w-auto">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="rounded-lg border border-violet-200 bg-violet-50 px-3 py-1.5 text-[13px] font-medium text-violet-900 transition-colors hover:bg-violet-100 disabled:cursor-wait disabled:opacity-60"
      >
        {pending ? "KI prüft Unstimmigkeiten…" : "Unstimmigkeiten prüfen (KI)"}
      </button>
      {error && <p role="alert" className="max-w-2xl text-xs text-red-600">{error}</p>}
      <div aria-live="polite" className="w-full">
        {result && <ResultPanel entityType={entityType} result={result} />}
      </div>
    </div>
  );
}
