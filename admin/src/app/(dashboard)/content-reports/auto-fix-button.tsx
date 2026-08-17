"use client";

// Button + Ergebnisanzeige für den automatischen Fix EINER Meldung —
// Nutzerwunsch: "baue ein, dass von nutzer gemeldete fehler automatisch
// (und auf button befehl) gefixxt und behoben werden. dazu soll auch immer
// ein bericht erstellt werden." Der "Bericht" selbst liegt dauerhaft in
// content_report_fixes (siehe FixHistory unten) — dieser Button zeigt nur
// das Ergebnis des GERADE ausgelösten Versuchs unmittelbar an, ohne auf
// einen Seiten-Reload warten zu müssen.

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { autoFixContentReport, type AutoFixResult } from "./actions";

const STATUS_STYLE: Record<AutoFixResult["status"], string> = {
  fixed: "bg-green-50 text-green-800 border-green-200",
  needs_manual_review: "bg-amber-50 text-amber-800 border-amber-200",
  error: "bg-red-50 text-red-700 border-red-200",
  code_bug_suspected: "bg-purple-50 text-purple-800 border-purple-200",
};

const STATUS_LABEL: Record<AutoFixResult["status"], string> = {
  fixed: "Automatisch behoben",
  needs_manual_review: "Manuelle Prüfung nötig",
  error: "Fehler beim Fix-Versuch",
  code_bug_suspected: "Struktureller Fehler erkannt",
};

export function AutoFixButton({
  reportId,
  alreadyTried = false,
}: {
  reportId: string;
  /** Ändert nur Label/Styling ("Erneut versuchen" statt "Automatisch
   * fixen") — macht sichtbar, dass hier schon ein Diagnose-Bericht in der
   * Karte darunter steht, statt dass der Button bei jeder Meldung gleich
   * aussieht, egal ob schon etwas probiert wurde (Nutzerfeedback: "sehr
   * unübersichtlich gestaltet"). */
  alreadyTried?: boolean;
}) {
  const [pending, startTransition] = useTransition();
  const router = useRouter();
  const [result, setResult] = useState<AutoFixResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    startTransition(async () => {
      try {
        const r = await autoFixContentReport(reportId, alreadyTried);
        setResult(r);
        router.refresh();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Automatischer Fix fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="rounded-lg bg-[#0071e3] px-2.5 py-1.5 text-xs font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
      >
        {pending ? "Prüfe & fixe…" : alreadyTried ? "Erneut versuchen" : "Automatisch fixen"}
      </button>
      {error && <p className="max-w-xs text-right text-xs text-red-600">{error}</p>}
      {result && <p className={`rounded-md border px-2 py-1 text-xs font-medium ${STATUS_STYLE[result.status]}`}>{STATUS_LABEL[result.status]}</p>}
    </div>
  );
}
