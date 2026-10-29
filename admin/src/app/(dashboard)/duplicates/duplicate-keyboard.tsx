"use client";

import { useEffect, useState } from "react";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Tastatursteuerung für
// die Duplikat-Prüfung. J/↓ und K/↑ wählen ein Paar, A bzw. B behält die
// linke bzw. rechte Version, V markiert als verschieden. Danach rückt das
// nächste Paar automatisch nach (die Liste lädt ohne das erledigte Paar neu).

const SELECTOR = "[data-pair]";

function pairs() {
  return Array.from(document.querySelectorAll<HTMLElement>(SELECTOR));
}

export function DuplicateKeyboard() {
  const [index, setIndex] = useState(0);
  const [enabled, setEnabled] = useState(true);

  useEffect(() => {
    const list = pairs();
    list.forEach((element, i) => {
      element.dataset.active = i === Math.min(index, list.length - 1) && enabled ? "true" : "false";
    });
  });

  useEffect(() => {
    if (!enabled) return;
    function onKey(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      if (target && (target.closest("input, textarea, select, [contenteditable=true]") || event.metaKey || event.ctrlKey || event.altKey)) return;
      const list = pairs();
      if (!list.length) return;
      const current = Math.min(index, list.length - 1);
      const key = event.key.toLowerCase();
      if (key === "j" || key === "arrowdown") {
        event.preventDefault();
        const next = Math.min(current + 1, list.length - 1);
        setIndex(next);
        list[next].scrollIntoView({ block: "nearest", behavior: "smooth" });
        return;
      }
      if (key === "k" || key === "arrowup") {
        event.preventDefault();
        const previous = Math.max(current - 1, 0);
        setIndex(previous);
        list[previous].scrollIntoView({ block: "nearest", behavior: "smooth" });
        return;
      }
      if (key === "a" || key === "b" || key === "v") {
        const button = list[current].querySelector<HTMLButtonElement>(`[data-shortcut="${key}"] button`);
        if (button && !button.disabled) {
          event.preventDefault();
          button.click();
        }
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [index, enabled]);

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg bg-neutral-50 px-3 py-2 text-xs text-neutral-600">
      <label className="flex items-center gap-1.5 font-medium text-neutral-700">
        <input type="checkbox" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} className="size-3.5 accent-[#2D2A6E]" />
        Tastatur
      </label>
      <span>
        <Kbd>J</Kbd>/<Kbd>K</Kbd> nächstes/voriges Paar
      </span>
      <span>
        <Kbd>A</Kbd> links behalten
      </span>
      <span>
        <Kbd>B</Kbd> rechts behalten
      </span>
      <span>
        <Kbd>V</Kbd> verschieden
      </span>
    </div>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return <kbd className="rounded border border-black/15 bg-white px-1.5 py-0.5 font-mono text-[11px] text-neutral-800 shadow-sm">{children}</kbd>;
}
