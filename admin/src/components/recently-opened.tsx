"use client";

import Link from "next/link";
import { useSyncExternalStore } from "react";
import { RECENT_STORAGE_KEY, readRecent, type RecentEntry } from "@/components/recent-tracker";

// Erstellt von Claude Code (29.10.2026): "Zuletzt geöffnet" auf /admin.

function subscribe(onChange: () => void) {
  window.addEventListener("storage", onChange);
  return () => window.removeEventListener("storage", onChange);
}

function snapshot() {
  try {
    return window.localStorage.getItem(RECENT_STORAGE_KEY) ?? "[]";
  } catch {
    return "[]";
  }
}

const relative = new Intl.RelativeTimeFormat("de-DE", { numeric: "auto" });
function ago(at: number, now: number) {
  const minutes = Math.round((at - now) / 60000);
  if (Math.abs(minutes) < 60) return relative.format(minutes, "minute");
  const hours = Math.round(minutes / 60);
  if (Math.abs(hours) < 24) return relative.format(hours, "hour");
  return relative.format(Math.round(hours / 24), "day");
}

export function RecentlyOpened() {
  const raw = useSyncExternalStore(subscribe, snapshot, () => "[]");
  const entries: RecentEntry[] = raw === "[]" ? [] : readRecent();
  const now = entries[0]?.at ? Math.max(...entries.map((entry) => entry.at)) : 0;

  if (!entries.length) {
    return <p className="text-sm text-neutral-500">Hier erscheinen die Datensätze, die du zuletzt geöffnet hast.</p>;
  }
  return (
    <ul className="flex flex-col divide-y divide-black/[0.05] rounded-xl border border-black/[0.06] bg-white shadow-sm">
      {entries.slice(0, 8).map((entry) => (
        <li key={entry.href}>
          <Link href={entry.href} className="flex items-center justify-between gap-3 px-4 py-2.5 hover:bg-neutral-50">
            <span className="min-w-0">
              <span className="mr-2 rounded bg-neutral-100 px-1.5 py-0.5 text-[11px] text-neutral-600">{entry.kind}</span>
              <span className="text-sm font-medium text-neutral-900">{entry.title}</span>
            </span>
            <span className="shrink-0 text-xs text-neutral-400">{entry.at === now ? "zuletzt" : ago(entry.at, now)}</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}
