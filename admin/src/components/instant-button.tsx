"use client";

import { useState, useTransition } from "react";

// Wie ConfirmButton, aber ohne Bestätigungsschritt — für Aktionen, die
// reversibel genug sind, dass ein einzelner Klick reicht (siehe
// entity-candidates/candidate-list.tsx, wo dasselbe Muster zuerst entstand:
// Ablehnen/Freigeben eines Kandidaten ist kein "abwägiger Sonderfall").
// Extrahiert hierher, damit die konsolidierte Duplikate-Seite (duplicates/
// page.tsx) dieselbe Namensvetter-Karte ohne window.confirm() zeigen kann.
export function InstantButton({
  action,
  className,
  children,
  pendingLabel = "Speichere…",
}: {
  action: () => Promise<void>;
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
              await action();
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
