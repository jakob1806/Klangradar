"use client";

// Button + Ergebnisanzeige für den automatischen Fix EINER Meldung —
// Nutzerwunsch: "baue ein, dass von nutzer gemeldete fehler automatisch
// (und auf button befehl) gefixxt und behoben werden. dazu soll auch immer
// ein bericht erstellt werden." Der "Bericht" selbst liegt dauerhaft in
// content_report_fixes (siehe FixHistory unten) — dieser Button zeigt nur
// das Ergebnis des GERADE ausgelösten Versuchs unmittelbar an, ohne auf
// einen Seiten-Reload warten zu müssen.

import { useState, useTransition } from "react";
import { autoFixContentReport, type AutoFixResult } from "./actions";

const STATUS_STYLE: Record<AutoFixResult["status"], string> = {
  fixed: "bg-green-50 text-green-800 border-green-200",
  needs_manual_review: "bg-amber-50 text-amber-800 border-amber-200",
  error: "bg-red-50 text-red-700 border-red-200",
};

const STATUS_LABEL: Record<AutoFixResult["status"], string> = {
  fixed: "Automatisch behoben",
  needs_manual_review: "Manuelle Prüfung nötig",
  error: "Fehler beim Fix-Versuch",
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
  const [result, setResult] = useState<AutoFixResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    startTransition(async () => {
      try {
        const r = await autoFixContentReport(reportId);
        setResult(r);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Automatischer Fix fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="flex flex-col items-end gap-1.5">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="rounded-md border border-blue-200 bg-blue-50 px-2.5 py-1.5 text-xs font-medium text-blue-800 hover:bg-blue-100 disabled:opacity-50"
      >
        {pending ? "Prüfe & fixe…" : alreadyTried ? "Erneut versuchen" : "Automatisch fixen"}
      </button>
      {error && <p className="max-w-xs text-right text-xs text-red-600">{error}</p>}
      {result && (
        <div className={`max-w-xs rounded-md border px-2.5 py-1.5 text-right text-xs ${STATUS_STYLE[result.status]}`}>
          <p className="font-medium">{STATUS_LABEL[result.status]}</p>
          <p className="mt-0.5">{result.diagnosis}</p>
        </div>
      )}
    </div>
  );
}
