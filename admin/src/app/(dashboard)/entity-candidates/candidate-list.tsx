"use client";

// Nutzeranfrage: "ablehnen und freigeben button, sowie zusammenführen
// button nur einmal drücken, nicht immer danach noch einmal bestätigen
// müssen. nur im äußersten sonderfall bei einer sehr abwägigen
// entscheidung" + "mehrfachauswahl um mehrere hinzuzufügen" + "score
// einfügen, bei dem du alle mit über 60% in eine eigene kategorie setzt,
// bei denen man mit einem button direkt alle genehmigen kann".
//
// Ablehnen/Freigeben sind reversibel-genug (ein abgelehnter Kandidat kann
// erneut auftauchen, ein freigegebener ist nur ein unverifizierter
// Stammdaten-Eintrag, der sich normal löschen lässt) — deshalb hier ohne
// window.confirm/ConfirmButton. Einzige Ausnahme: Zusammenführen bei
// niedriger Ähnlichkeit (< 70%) bleibt ein "abwägiger Sonderfall" (echtes
// Risiko, zwei verschiedene Personen versehentlich zu verschmelzen) und
// behält die Bestätigung.

import { useState, useTransition } from "react";
import {
  approveEntityCandidate,
  bulkApproveEntityCandidates,
  bulkRejectEntityCandidates,
  rejectEntityCandidate,
  sendEntityCandidateToDuplicateReview,
} from "./actions";

const ENTITY_TYPE_LABEL: Record<string, string> = {
  person: "Person",
  ensemble: "Ensemble",
  organizer: "Institution",
};

export interface UiCandidate {
  id: string;
  entityType: string;
  name: string;
  suggestedEventTitle: string | null;
  suggestedEventStart: string | null;
  venueName: string | null;
  sourceUrl: string | null;
  createdAt: string;
  bioSnippet: string | null;
  websiteUrl: string | null;
  possibleMatch: { id: string; name: string; similarity: number } | null;
  score: number;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

function InstantButton({
  onClick,
  className,
  children,
  pendingLabel = "Speichere…",
}: {
  onClick: () => Promise<void>;
  className: string;
  children: React.ReactNode;
  pendingLabel?: string;
}) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <span className="inline-flex flex-col items-end gap-1">
      <button
        type="button"
        disabled={pending}
        onClick={() => {
          setError(null);
          startTransition(async () => {
            try {
              await onClick();
            } catch (err) {
              setError(err instanceof Error ? err.message : "Aktion fehlgeschlagen.");
            }
          });
        }}
        className={className}
      >
        {pending ? pendingLabel : children}
      </button>
      {error && <span className="max-w-xs text-right text-xs text-red-600">{error}</span>}
    </span>
  );
}

function CandidateMeta({ candidate }: { candidate: UiCandidate }) {
  return (
    <div className="mt-3 rounded-md border border-neutral-100 bg-neutral-50 p-3">
      <p className="text-sm font-medium text-neutral-900">{candidate.name}</p>
      {candidate.suggestedEventTitle && (
        <p className="mt-1 text-xs text-neutral-500">
          Anlass: {candidate.suggestedEventTitle}
          {candidate.venueName ? ` · ${candidate.venueName}` : ""}
          {candidate.suggestedEventStart ? ` · ${formatDate(candidate.suggestedEventStart)}` : ""}
        </p>
      )}
      {candidate.sourceUrl && (
        <a
          href={candidate.sourceUrl}
          target="_blank"
          rel="noreferrer"
          className="mt-1 block truncate text-xs text-blue-600 hover:underline"
        >
          {candidate.sourceUrl}
        </a>
      )}
      {candidate.bioSnippet && <p className="mt-2 text-xs text-neutral-600">{candidate.bioSnippet}</p>}
      {candidate.websiteUrl && (
        <a
          href={candidate.websiteUrl}
          target="_blank"
          rel="noreferrer"
          className="mt-1 block truncate text-xs text-blue-600 hover:underline"
        >
          {candidate.websiteUrl}
        </a>
      )}
    </div>
  );
}

function ScoreBadge({ score }: { score: number }) {
  const color =
    score >= 60 ? "bg-emerald-50 text-emerald-700" : score >= 30 ? "bg-amber-50 text-amber-700" : "bg-neutral-100 text-neutral-500";
  return (
    <span
      className={`rounded px-1.5 py-0.5 text-[10px] font-medium ${color}`}
      title="Konfidenz-Score: +40 für eine per KI-Websuche gefundene Kurzbiografie, +30 für eine gefundene offizielle Website, +30 wenn der Name wie ein vollständiger Vor-/Nachname aussieht. Ab 60% gilt ein Kandidat als hinreichend sicher für eine Sammel-Freigabe."
    >
      Score {score}%
    </span>
  );
}

function MergeCandidateCard({ candidate, onDone }: { candidate: UiCandidate; onDone: () => void }) {
  const match = candidate.possibleMatch!;

  return (
    <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
      <span className="text-xs text-neutral-400">
        Gefunden {formatDate(candidate.createdAt)} · {ENTITY_TYPE_LABEL[candidate.entityType] ?? candidate.entityType}
      </span>
      <CandidateMeta candidate={candidate} />
      <p className="mt-2 rounded bg-amber-50 px-2 py-1 text-xs text-amber-800">
        Möglicherweise identisch mit „{match.name}“ ({Math.round(match.similarity * 100)}% Namens-Ähnlichkeit) — bereits
        vorhanden. Wird zur Duplikat-Prüfung geschickt ({candidate.entityType === "person" ? "Personen" : "Ensemble"}
        -Duplikate), wo du auswählst, welche der beiden Versionen erhalten bleibt.
      </p>
      <div className="mt-4 flex items-center justify-end gap-4">
        <InstantButton
          onClick={async () => {
            await rejectEntityCandidate(candidate.id);
            onDone();
          }}
          className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
        >
          Ablehnen
        </InstantButton>
        <InstantButton
          onClick={async () => {
            await sendEntityCandidateToDuplicateReview(candidate.id, match.id);
            onDone();
          }}
          className="text-sm font-medium text-amber-700 hover:text-amber-900 disabled:opacity-50"
          pendingLabel="Sende…"
        >
          Zur Duplikat-Prüfung schicken
        </InstantButton>
        <InstantButton
          onClick={async () => {
            await approveEntityCandidate(candidate.id);
            onDone();
          }}
          className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
        >
          Trotzdem als neu anlegen
        </InstantButton>
      </div>
    </div>
  );
}

function useSelection() {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }
  function setAll(ids: string[]) {
    setSelected(new Set(ids));
  }
  function clear() {
    setSelected(new Set());
  }
  return { selected, toggle, setAll, clear };
}

function NewCandidateCard({
  candidate,
  selectable,
  selected,
  onToggle,
  onDone,
}: {
  candidate: UiCandidate;
  selectable: boolean;
  selected: boolean;
  onToggle: () => void;
  onDone: () => void;
}) {
  return (
    <div className="flex gap-3 rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
      {selectable && (
        <input
          type="checkbox"
          className="mt-1 h-4 w-4 shrink-0 rounded border-neutral-300"
          checked={selected}
          onChange={onToggle}
          aria-label="Auswählen"
        />
      )}
      <div className="flex-1">
        <div className="flex items-center justify-between gap-4">
          <span className="text-xs text-neutral-400">
            Gefunden {formatDate(candidate.createdAt)} · {ENTITY_TYPE_LABEL[candidate.entityType] ?? candidate.entityType}
          </span>
          <ScoreBadge score={candidate.score} />
        </div>
        <CandidateMeta candidate={candidate} />
        <div className="mt-4 flex items-center justify-end gap-4">
          <InstantButton
            onClick={async () => {
              await rejectEntityCandidate(candidate.id);
              onDone();
            }}
            className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
          >
            Ablehnen
          </InstantButton>
          <InstantButton
            onClick={async () => {
              await approveEntityCandidate(candidate.id);
              onDone();
            }}
            className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50"
          >
            Freigeben
          </InstantButton>
        </div>
      </div>
    </div>
  );
}

export function CandidateList({
  mergeCandidates,
  highConfidence,
  lowConfidence,
}: {
  mergeCandidates: UiCandidate[];
  highConfidence: UiCandidate[];
  lowConfidence: UiCandidate[];
}) {
  const [dismissed, setDismissed] = useState<Set<string>>(new Set());
  const dismiss = (id: string) => setDismissed((prev) => new Set(prev).add(id));

  const visibleMerge = mergeCandidates.filter((c) => !dismissed.has(c.id));
  const visibleHigh = highConfidence.filter((c) => !dismissed.has(c.id));
  const visibleLow = lowConfidence.filter((c) => !dismissed.has(c.id));

  const lowSelection = useSelection();
  const [bulkPending, startBulkTransition] = useTransition();
  const [bulkError, setBulkError] = useState<string | null>(null);

  function bulkApproveAllHigh() {
    setBulkError(null);
    const ids = visibleHigh.map((c) => c.id);
    startBulkTransition(async () => {
      try {
        await bulkApproveEntityCandidates(ids);
        ids.forEach(dismiss);
      } catch (err) {
        setBulkError(err instanceof Error ? err.message : "Aktion fehlgeschlagen.");
      }
    });
  }

  function bulkAct(selection: ReturnType<typeof useSelection>, action: "approve" | "reject") {
    setBulkError(null);
    const ids = Array.from(selection.selected);
    if (ids.length === 0) return;
    startBulkTransition(async () => {
      try {
        if (action === "approve") await bulkApproveEntityCandidates(ids);
        else await bulkRejectEntityCandidates(ids);
        ids.forEach(dismiss);
        selection.clear();
      } catch (err) {
        setBulkError(err instanceof Error ? err.message : "Aktion fehlgeschlagen.");
      }
    });
  }

  if (mergeCandidates.length === 0 && highConfidence.length === 0 && lowConfidence.length === 0) {
    return (
      <div className="border-2 border-dashed border-neutral-300 bg-white px-4 py-10 text-center text-sm text-neutral-400">
        Keine offenen Entity-Kandidaten.
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-10">
      {bulkError && <p className="text-sm text-red-600">{bulkError}</p>}

      {visibleMerge.length > 0 && (
        <section>
          <h2 className="text-sm font-semibold text-neutral-900">Mögliche Duplikate ({visibleMerge.length})</h2>
          <div className="mt-3 flex flex-col gap-3">
            {visibleMerge.map((c) => (
              <MergeCandidateCard key={c.id} candidate={c} onDone={() => dismiss(c.id)} />
            ))}
          </div>
        </section>
      )}

      {visibleHigh.length > 0 && (
        <section>
          <div className="flex items-center justify-between gap-4">
            <h2 className="text-sm font-semibold text-neutral-900">
              Hohe Konfidenz — Score über 60% ({visibleHigh.length})
            </h2>
            <button
              type="button"
              disabled={bulkPending}
              onClick={bulkApproveAllHigh}
              className="border-2 border-emerald-700 bg-emerald-700 px-3 py-1.5 text-sm font-medium text-white hover:bg-emerald-800 disabled:opacity-50"
            >
              {bulkPending ? "Speichere…" : `Alle ${visibleHigh.length} genehmigen`}
            </button>
          </div>
          <div className="mt-3 flex flex-col gap-3">
            {visibleHigh.map((c) => (
              <NewCandidateCard
                key={c.id}
                candidate={c}
                selectable={false}
                selected={false}
                onToggle={() => {}}
                onDone={() => dismiss(c.id)}
              />
            ))}
          </div>
        </section>
      )}

      {visibleLow.length > 0 && (
        <section>
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              className="h-4 w-4 rounded border-neutral-300"
              checked={visibleLow.length > 0 && lowSelection.selected.size === visibleLow.length}
              onChange={(e) =>
                e.target.checked ? lowSelection.setAll(visibleLow.map((c) => c.id)) : lowSelection.clear()
              }
              aria-label="Alle auswählen"
            />
            <h2 className="text-sm font-semibold text-neutral-900">Weitere Kandidaten ({visibleLow.length})</h2>
          </div>
          {lowSelection.selected.size > 0 && (
            <div className="mt-3 flex items-center justify-between rounded-xl border border-black/[0.06] bg-black/[0.02] px-4 py-2 text-sm">
              <span className="text-neutral-600">{lowSelection.selected.size} ausgewählt</span>
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  disabled={bulkPending}
                  onClick={() => bulkAct(lowSelection, "reject")}
                  className="rounded-lg border border-black/10 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-black/[0.04] disabled:opacity-50"
                >
                  Ablehnen
                </button>
                <button
                  type="button"
                  disabled={bulkPending}
                  onClick={() => bulkAct(lowSelection, "approve")}
                  className="rounded-lg bg-[#0071e3] px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
                >
                  Genehmigen
                </button>
              </div>
            </div>
          )}
          <div className="mt-3 flex flex-col gap-3">
            {visibleLow.map((c) => (
              <NewCandidateCard
                key={c.id}
                candidate={c}
                selectable
                selected={lowSelection.selected.has(c.id)}
                onToggle={() => lowSelection.toggle(c.id)}
                onDone={() => dismiss(c.id)}
              />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
