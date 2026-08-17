"use client";

import { useState, useTransition } from "react";
import { autoFixAllPendingReports } from "./actions";

/** Sammel-Fix für alle offenen Meldungen der aktuellen App — einschließlich
 * früherer manueller/fehlgeschlagener Versuche. */
export function AutoFixAllButton({ platform }: { platform: "flutter" | "native" }) {
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    setMessage(null);
    startTransition(async () => {
      try {
        const { processed } = await autoFixAllPendingReports(platform, 20);
        setMessage(processed === 0 ? "Keine offenen Meldungen." : `${processed} Meldung(en) erneut geprüft.`);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="rounded-lg bg-[#0071e3] px-3.5 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
      >
        {pending ? "Reparaturen laufen…" : "Alle offenen reparieren"}
      </button>
      {message && <span className="text-xs text-neutral-500">{message}</span>}
      {error && <span className="text-xs text-red-600">{error}</span>}
    </div>
  );
}
