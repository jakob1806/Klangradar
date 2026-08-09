"use client";

import { useState, useTransition } from "react";
import { resolveEntityCandidatesWithAi } from "./actions";

const BATCH_SIZE = 12;
const MAX_ROUNDS = 30; // Sicherheitsdeckel (bis zu 360 Kandidaten pro Klick)

interface RunningTotals {
  rounds: number;
  processed: number;
  approved: number;
  leftPending: number;
  errors: string[];
}

const EMPTY_TOTALS: RunningTotals = { rounds: 0, processed: 0, approved: 0, leftPending: 0, errors: [] };

/** Batch-Button: schickt wartende person/ensemble-Kandidaten durch dieselbe
 * Tavily+LLM-Prüfung, die neue Kandidaten schon automatisch entscheidet
 * (siehe resolve-entity-candidates Edge Function) — holt das für die schon
 * bestehende Warteliste nach, die von der laufenden Automatik nicht
 * rückwirkend erfasst wird.
 *
 * Läuft automatisch in mehreren Runden à 12 weiter (statt nach jeder Runde
 * auf einen erneuten Klick zu warten), bis entweder nichts mehr offen ist
 * (totalRemainingPending === 0 oder eine Runde liefert weniger als
 * BATCH_SIZE zurück — dann ist die Warteliste erschöpft) oder der
 * Sicherheitsdeckel MAX_ROUNDS erreicht ist. Zeigt die Gesamtzahl noch
 * offener Kandidaten live an, damit bei einer großen Warteliste sichtbar
 * ist, dass sich tatsächlich etwas tut, statt dass jede Runde wie
 * "dasselbe Ergebnis" aussieht. */
export function ResolveWithAiButton() {
  const [pending, startTransition] = useTransition();
  const [totals, setTotals] = useState<RunningTotals | null>(null);
  const [remaining, setRemaining] = useState<number | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [stopped, setStopped] = useState(false);

  function run() {
    setFailure(null);
    setStopped(false);
    startTransition(async () => {
      let acc = { ...EMPTY_TOTALS };
      for (let round = 0; round < MAX_ROUNDS; round++) {
        const result = await resolveEntityCandidatesWithAi();
        if (result.status === "failed") {
          setFailure(result.error ?? "Unbekannter Fehler.");
          setTotals(acc);
          return;
        }

        acc = {
          rounds: acc.rounds + 1,
          processed: acc.processed + (result.processed ?? 0),
          approved: acc.approved + (result.approved ?? 0),
          leftPending: acc.leftPending + (result.leftPending ?? 0),
          errors: [...acc.errors, ...(result.errors ?? [])],
        };
        setTotals(acc);
        setRemaining(result.totalRemainingPending ?? null);

        const batchWasFull = (result.processed ?? 0) >= BATCH_SIZE;
        const stillSomethingPending = (result.totalRemainingPending ?? 0) > 0;
        if (!batchWasFull || !stillSomethingPending) return;
      }
      setStopped(true);
    });
  }

  return (
    <div className="flex flex-col items-end gap-2">
      {remaining !== null && (
        <p className="text-xs text-neutral-500">{remaining} Personen/Ensembles insgesamt noch offen</p>
      )}
      <button
        type="button"
        disabled={pending}
        onClick={run}
        className="border-2 border-[#171717] bg-[#171717] px-4 py-2 type-label !text-white hover:bg-white hover:!text-[#171717] disabled:opacity-50"
      >
        {pending ? `KI prüft… (Runde ${(totals?.rounds ?? 0) + 1})` : "Mit KI prüfen"}
      </button>
      {totals && (totals.rounds > 0 || failure) && (
        <p className="max-w-xs text-right text-xs text-neutral-600">
          {totals.rounds} Runde{totals.rounds === 1 ? "" : "n"} · {totals.processed} geprüft ·{" "}
          {totals.approved} automatisch angelegt · {totals.leftPending} weiterhin unklar
          {stopped && <span className="mt-1 block text-amber-700">Sicherheitsdeckel erreicht — einfach nochmal klicken.</span>}
          {totals.errors.length > 0 && <span className="mt-1 block text-red-600">{totals.errors.join("; ")}</span>}
        </p>
      )}
      {failure && <p className="max-w-xs text-right text-xs text-red-600">{failure}</p>}
    </div>
  );
}
