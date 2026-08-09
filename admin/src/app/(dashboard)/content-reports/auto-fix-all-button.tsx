"use client";

import { useState, useTransition } from "react";
import { autoFixAllPendingReports } from "./actions";

/** Sammel-Fix für alle noch nie versuchten offenen Meldungen — nach einem
 * Lauf lädt die Seite über revalidatePath in der Server Action neu, die
 * fertig bearbeiteten Meldungen verschwinden dann automatisch aus der
 * pending-Liste (oder zeigen ihren neuen Diagnose-Bericht, siehe
 * FixHistory in page.tsx). */
export function AutoFixAllButton() {
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    setMessage(null);
    startTransition(async () => {
      try {
        const { processed } = await autoFixAllPendingReports(10);
        setMessage(processed === 0 ? "Keine neuen Meldungen zu prüfen." : `${processed} Meldung(en) geprüft.`);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="rounded-full bg-[#0071e3] px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
      >
        {pending ? "Prüfe alle offenen Meldungen…" : "Alle offenen automatisch prüfen"}
      </button>
      {message && <span className="text-xs text-neutral-500">{message}</span>}
      {error && <span className="text-xs text-red-600">{error}</span>}
    </div>
  );
}
