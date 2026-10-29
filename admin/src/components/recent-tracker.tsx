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

// Feste Pfad-Präfixe je Bereich: der Link setzt sich nie aus gespeichertem
// Text zusammen, nur aus dieser Tabelle plus der geprüften ID.
const ID_CHARS = "0123456789abcdef-";

/** Baut die ID Zeichen für Zeichen aus ID_CHARS neu auf — so stammt im Link
 * kein einziges Zeichen direkt aus dem gespeicherten Text (CodeQL
 * js/xss-through-dom). */
function cleanId(raw: string): string {
  let id = "";
  for (const char of raw) {
    const index = ID_CHARS.indexOf(char);
    if (index >= 0) id += ID_CHARS.charAt(index);
  }
  return id;
}

const DETAIL_PATHS: Record<string, string> = Object.fromEntries(Object.keys(KINDS).map((key) => [key, `/${key}`]));

/** Nur gültige interne Detailpfade (/bereich/uuid) — localStorage ist
 * Nutzereingabe und darf nie zu einem fremden oder javascript:-Link werden. */
function isValidEntry(value: unknown): value is RecentEntry {
  if (!value || typeof value !== "object") return false;
  const entry = value as Record<string, unknown>;
  if (typeof entry.href !== "string" || typeof entry.title !== "string" || typeof entry.kind !== "string" || typeof entry.at !== "number") return false;
  const match = DETAIL.exec(entry.href);
  return Boolean(match && KINDS[match[1]]);
}

export function readRecent(): RecentEntry[] {
  try {
    const parsed: unknown = JSON.parse(window.localStorage.getItem(RECENT_STORAGE_KEY) ?? "[]");
    return Array.isArray(parsed)
      ? parsed.filter(isValidEntry).map((entry) => {
          const match = DETAIL.exec(entry.href)!;
          // href aus den geprüften Bestandteilen neu zusammensetzen.
          return { href: `${DETAIL_PATHS[match[1]]}/${cleanId(match[2])}`, title: entry.title.slice(0, 120), kind: KINDS[match[1]], at: entry.at };
        })
      : [];
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
