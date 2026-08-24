"use client";

import { useRouter } from "next/navigation";
import { useCallback, useState, useTransition } from "react";
import {
  applyEditorialAiProposals,
  type EditorialAiProposal,
} from "@/lib/editorial-ai-actions";
import {
  resolveEntityAuditFlag,
  suggestEntityAuditCorrection,
  type AuditableEntityType,
  type EntityAuditCorrection,
} from "@/lib/entity-audit-actions";

const CONFIDENCE_LABEL: Record<EditorialAiProposal["confidence"], string> = {
  confirmed: "Bestätigt",
  likely: "Wahrscheinlich",
  unclear: "Unklar",
};

const CONFIDENCE_STYLE: Record<EditorialAiProposal["confidence"], string> = {
  confirmed: "bg-emerald-100 text-emerald-800",
  likely: "bg-amber-100 text-amber-800",
  unclear: "bg-neutral-200 text-neutral-600",
};

function formatValue(value: unknown): string {
  if (value == null) return "—";
  if (Array.isArray(value)) return value.join(", ") || "—";
  return String(value);
}

/** Fragt für ein einzelnes gemeldetes Datenqualitätsproblem einen
 * KI-Korrekturvorschlag an (recherchegestützt, reuses den bestehenden
 * editorial-ai-assistant-Chat statt einer eigenen Recherche-Pipeline) und
 * wendet ihn nach Freigabe direkt an — Nutzervorgabe "Fehler [sollen]
 * automatisch korrigiert werden können, wenn das genehmigt wurde". Nach dem
 * Übernehmen wird die Auffälligkeit automatisch als erledigt markiert. */
export function EntityAuditFixButton({
  entityType,
  entityId,
  flagId,
  issueMessage,
  issueSuggestion,
  initialCorrection,
}: {
  entityType: AuditableEntityType;
  entityId: string;
  flagId: string;
  issueMessage: string;
  issueSuggestion?: string | null;
  initialCorrection?: EntityAuditCorrection | null;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [suggesting, setSuggesting] = useState(false);
  const [applying, setApplying] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [answer, setAnswer] = useState<string | null>(initialCorrection?.answer ?? null);
  const [proposals, setProposals] = useState<EditorialAiProposal[]>(initialCorrection?.proposals ?? []);
  const [correctionReady, setCorrectionReady] = useState(Boolean(initialCorrection));
  const [appliedFields, setAppliedFields] = useState<string[]>([]);

  const runSuggestion = useCallback(async (force = false) => {
    setError(null);
    if (force) {
      setAnswer(null);
      setProposals([]);
      setAppliedFields([]);
    }
    setSuggesting(true);
    try {
      const result = await suggestEntityAuditCorrection(
        flagId,
        entityType,
        entityId,
        issueMessage,
        issueSuggestion,
        force,
      );
      setAnswer(result.answer);
      setProposals(result.proposals);
      setCorrectionReady(true);
    } catch (suggestError) {
      setError(suggestError instanceof Error ? suggestError.message : "KI-Vorschlag fehlgeschlagen.");
    } finally {
      setSuggesting(false);
    }
  }, [entityId, entityType, flagId, issueMessage, issueSuggestion]);

  function handleApply(proposal: EditorialAiProposal) {
    setApplying(proposal.field);
    setError(null);
    startTransition(async () => {
      try {
        await applyEditorialAiProposals(entityType, entityId, [proposal]);
        const remainingSafe = proposals.filter(
          (candidate) =>
            candidate.confidence !== "unclear" &&
            candidate.field !== proposal.field &&
            !appliedFields.includes(candidate.field),
        );
        if (remainingSafe.length === 0) await resolveEntityAuditFlag(flagId);
        setAppliedFields((f) => [...f, proposal.field]);
        router.refresh();
      } catch (applyError) {
        setError(applyError instanceof Error ? applyError.message : "Übernehmen fehlgeschlagen.");
      } finally {
        setApplying(null);
      }
    });
  }

  function handleApplyAll() {
    const safeProposals = proposals.filter(
      (proposal) => proposal.confidence !== "unclear" && !appliedFields.includes(proposal.field),
    );
    if (safeProposals.length === 0) return;
    setApplying("__all__");
    setError(null);
    startTransition(async () => {
      try {
        await applyEditorialAiProposals(entityType, entityId, safeProposals);
        await resolveEntityAuditFlag(flagId);
        setAppliedFields((fields) => [...fields, ...safeProposals.map((proposal) => proposal.field)]);
        router.refresh();
      } catch (applyError) {
        setError(applyError instanceof Error ? applyError.message : "Übernehmen fehlgeschlagen.");
      } finally {
        setApplying(null);
      }
    });
  }

  if (!correctionReady) {
    return (
      <div className="mt-3 rounded-lg border border-violet-100 bg-violet-50/50 px-3 py-2">
        <div className="flex items-center gap-2 text-xs font-medium text-violet-800">
          <span className={`h-2 w-2 rounded-full bg-violet-500 ${suggesting ? "animate-pulse" : ""}`} />
          {suggesting ? "KI recherchiert und erstellt einen Korrekturvorschlag…" : "KI-Korrektur ist in der Hintergrund-Warteschlange…"}
        </div>
        {error && <p className="max-w-xs text-right text-xs text-red-600">{error}</p>}
        {error && (
          <button type="button" onClick={() => void runSuggestion(true)} className="mt-1 text-xs font-medium text-violet-700">
            Erneut versuchen
          </button>
        )}
        {!suggesting && !error && (
          <button type="button" onClick={() => void runSuggestion(false)} className="mt-1 text-xs font-medium text-violet-700">
            Jetzt priorisieren
          </button>
        )}
      </div>
    );
  }

  return (
    <div className="mt-2 w-full max-w-lg rounded-md border border-violet-200 bg-violet-50/40 p-3 text-xs">
      {answer && <p className="text-neutral-700">{answer}</p>}
      {proposals.length === 0 ? (
        <p className="mt-1 text-neutral-500">Keine konkreten Feldvorschläge gefunden.</p>
      ) : (
        <>
        <div className="mt-2 flex flex-wrap items-center justify-between gap-2 border-b border-violet-100 pb-2">
          <span className="text-neutral-500">
            {proposals.length} {proposals.length === 1 ? "Änderung" : "Änderungen"} vorgeschlagen
          </span>
          {proposals.some((proposal) => proposal.confidence !== "unclear" && !appliedFields.includes(proposal.field)) && (
            <button
              type="button"
              disabled={pending}
              onClick={handleApplyAll}
              className="rounded-md bg-emerald-700 px-2.5 py-1.5 font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
            >
              {applying === "__all__" ? "Übernimmt alle…" : "Alle sicheren Änderungen übernehmen"}
            </button>
          )}
        </div>
        <ul className="mt-2 space-y-2">
          {proposals.map((proposal) => {
            const applied = appliedFields.includes(proposal.field);
            return (
              <li key={proposal.field} className="rounded-md border border-violet-200 bg-white p-2">
                <div className="flex flex-wrap items-center gap-2">
                  <code className="rounded bg-neutral-100 px-1.5 py-0.5 text-[11px]">{proposal.field}</code>
                  <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${CONFIDENCE_STYLE[proposal.confidence]}`}>
                    {CONFIDENCE_LABEL[proposal.confidence]}
                  </span>
                </div>
                <p className="mt-1 font-medium text-neutral-900">→ {formatValue(proposal.value)}</p>
                {proposal.rationale && <p className="mt-1 text-neutral-600">{proposal.rationale}</p>}
                {proposal.sourceUrls && proposal.sourceUrls.length > 0 && (
                  <p className="mt-1 truncate text-[10px] text-neutral-400">
                    Quelle: {proposal.sourceUrls[0]}
                  </p>
                )}
                <div className="mt-1.5">
                  {applied ? (
                    <span className="text-emerald-700">✓ Übernommen</span>
                  ) : proposal.confidence === "unclear" ? (
                    <span className="text-neutral-400">Zu unsicher zum automatischen Übernehmen</span>
                  ) : (
                    <button
                      type="button"
                      disabled={pending}
                      onClick={() => handleApply(proposal)}
                      className="font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
                    >
                      {applying === proposal.field ? "Übernimmt…" : "Übernehmen"}
                    </button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
        </>
      )}
      {error && <p className="mt-2 text-red-600">{error}</p>}
      <button
        type="button"
        disabled={pending || suggesting}
        onClick={() => void runSuggestion(true)}
        className="mt-2 text-neutral-500 hover:text-neutral-800 disabled:opacity-50"
      >
        {suggesting ? "KI recherchiert…" : "Neu recherchieren"}
      </button>
    </div>
  );
}
