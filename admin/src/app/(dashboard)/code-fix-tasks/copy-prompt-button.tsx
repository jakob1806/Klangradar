"use client";

import { useState } from "react";

// Kopiert den fertigen Auftragstext in die Zwischenablage, damit er direkt
// als Chatnachricht an Claude Code weitergegeben werden kann — Nutzerwunsch:
// "das ist dann wie, als würde ich dir eine chatnachricht mit der
// fehlerkorrektur schreiben".
export function CopyPromptButton({ prompt }: { prompt: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <button
      type="button"
      onClick={async () => {
        await navigator.clipboard.writeText(prompt);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
      className="rounded-lg border border-black/10 px-2.5 py-1.5 text-xs font-medium text-neutral-600 hover:bg-black/[0.04]"
    >
      {copied ? "Kopiert ✓" : "Auftragstext kopieren"}
    </button>
  );
}
