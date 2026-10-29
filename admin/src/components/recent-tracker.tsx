"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): merkt sich pro Browser
// die zuletzt geöffneten Datensätze (Detailseiten) für "Zuletzt geöffnet" auf
// der Startseite /admin. Nur im localStorage, nichts wird übertragen.

export const RECENT_STORAGE_KEY = "klangradar.admin.recent";
export type RecentEntry = { href: string; title: string; kind: string; at: number };

const KINDS: Record<string, string> = {
  events: "Termin",
  persons: "Person",
  ensembles: "Ensemble",
  venues: "Venue",
  works: "Werk",
  organizers: "Veranstalter",
  festivals: "Festival",
  "editorial-collections": "Sammlung",
  "event-groups": "Event-Gruppe",
};

const DETAIL = /^\/([a-z-]+)\/([0-9a-f-]{36})\/?$/;

export function readRecent(): RecentEntry[] {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(RECENT_STORAGE_KEY) ?? "[]");
    return Array.isArray(parsed) ? (parsed as RecentEntry[]) : [];
  } catch {
    return [];
  }
}

export function RecentTracker() {
  const pathname = usePathname();
  useEffect(() => {
    const match = pathname ? DETAIL.exec(pathname) : null;
    if (!match || !KINDS[match[1]]) return;
    // Überschrift erst nach dem Rendern lesen.
    const timer = window.setTimeout(() => {
      const heading = document.querySelector("main h1")?.textContent?.trim() ?? "";
      const title = heading.replace(/\s+bearbeiten$/i, "").slice(0, 120) || KINDS[match[1]];
      const entry: RecentEntry = { href: pathname!, title, kind: KINDS[match[1]], at: Date.now() };
      try {
        const next = [entry, ...readRecent().filter((item) => item.href !== entry.href)].slice(0, 12);
        window.localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(next));
      } catch {
        // Ohne localStorage (privates Fenster) gibt es keine Liste.
      }
    }, 600);
    return () => window.clearTimeout(timer);
  }, [pathname]);
  return null;
}
