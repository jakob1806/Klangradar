"use client";

import { useTransition } from "react";

/** Auf/Ab-Pfeile zum Verschieben eines Programmpunkts — reiner UI-Wrapper
 * um eine server-seitig gebundene moveWork-Aktion, analog zu den
 * bestehenden Auf/Ab-Buttons in der Bilder-Galerie
 * (components/entity-gallery/gallery-editor.tsx). */
export function MoveButtons({
  onMoveUp,
  onMoveDown,
  disableUp,
  disableDown,
}: {
  onMoveUp: () => Promise<void>;
  onMoveDown: () => Promise<void>;
  disableUp: boolean;
  disableDown: boolean;
}) {
  const [pending, startTransition] = useTransition();

  return (
    <span className="inline-flex flex-col gap-0.5">
      <button
        type="button"
        disabled={pending || disableUp}
        onClick={() => startTransition(onMoveUp)}
        aria-label="Nach oben verschieben"
        className="leading-none text-neutral-400 hover:text-neutral-800 disabled:opacity-30"
      >
        ▲
      </button>
      <button
        type="button"
        disabled={pending || disableDown}
        onClick={() => startTransition(onMoveDown)}
        aria-label="Nach unten verschieben"
        className="leading-none text-neutral-400 hover:text-neutral-800 disabled:opacity-30"
      >
        ▼
      </button>
    </span>
  );
}
