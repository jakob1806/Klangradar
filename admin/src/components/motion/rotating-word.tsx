"use client";

import { useEffect, useState } from "react";

// Wechselt ein Wort im Rhythmus (z. B. Städtenamen in der Hero-Zeile).
// Screenreader lesen die vollständige Liste statt des Wechsels.
export function RotatingWord({ words, intervalMs = 2200, className = "" }: { words: string[]; intervalMs?: number; className?: string }) {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const id = window.setInterval(() => setIndex((i) => (i + 1) % words.length), intervalMs);
    return () => window.clearInterval(id);
  }, [words.length, intervalMs]);

  return (
    <span className={`relative inline-block ${className}`}>
      <span className="sr-only">{words.join(", ")}</span>
      <span
        key={words[index]}
        aria-hidden="true"
        className="inline-block"
        style={{ animation: "fw-word-in 0.6s cubic-bezier(.2,.8,.2,1) both" }}
      >
        {words[index]}
      </span>
    </span>
  );
}
