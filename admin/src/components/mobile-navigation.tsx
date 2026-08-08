"use client";

import { useState, type MouseEvent, type ReactNode } from "react";

export function MobileNavigation({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);

  function closeAfterNavigation(event: MouseEvent<HTMLDivElement>) {
    if (event.target instanceof Element && event.target.closest("a")) setOpen(false);
  }

  return (
    <div className="min-w-0 flex-1">
      <div className="flex min-w-0 items-center gap-3">
        <button
          type="button"
          aria-label={open ? "Navigation schließen" : "Navigation öffnen"}
          aria-expanded={open}
          aria-controls="mobile-dashboard-navigation"
          onClick={() => setOpen((current) => !current)}
          className="inline-flex size-11 shrink-0 items-center justify-center rounded-lg border border-neutral-200 bg-white text-neutral-800 shadow-sm"
        >
          <span aria-hidden="true" className="flex w-5 flex-col gap-1.5">
            <span className="h-0.5 w-full rounded bg-current" />
            <span className="h-0.5 w-full rounded bg-current" />
            <span className="h-0.5 w-full rounded bg-current" />
          </span>
        </button>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold tracking-tight">Klassik München</p>
          <p className="truncate text-xs text-neutral-500">Redaktions-Dashboard</p>
        </div>
      </div>

      {open && (
        <div
          id="mobile-dashboard-navigation"
          onClick={closeAfterNavigation}
          className="mobile-navigation-panel absolute inset-x-3 top-[calc(100%-1px)] z-50 max-h-[min(72vh,38rem)] overflow-y-auto overscroll-contain rounded-b-xl border border-neutral-200 bg-white p-3 shadow-xl"
        >
          {children}
        </div>
      )}
    </div>
  );
}
