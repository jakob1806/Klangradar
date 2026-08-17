"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { formatMunichDateTime } from "@/lib/munich-time";
import { deleteEventGroup } from "./actions";
import { MergeGroupControl } from "./merge-group-control";

interface GroupRow {
  id: string;
  title: string;
  created_at: string;
  events: { id: string; title: string; start_datetime: string; venues: { name: string } | null }[];
}

// Client-Komponente statt Server-seitiger Filterung, weil die Gruppenliste
// bereits vollständig geladen ist (page.tsx lädt alle Gruppen für die
// Zusammenführungs-Vorschläge und MergeGroupControl ohnehin) — ein
// Suchfeld mit clientseitigem Filtern kommt ohne zusätzlichen Server-
// Roundtrip aus und bleibt bei der aktuellen Datenmenge performant.
function formatDate(iso: string) {
  return formatMunichDateTime(iso);
}

export function ExistingGroupsList({ groups }: { groups: GroupRow[] }) {
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLocaleLowerCase("de");
    if (!q) return groups;
    return groups.filter((g) => {
      if (g.title.toLocaleLowerCase("de").includes(q)) return true;
      return g.events.some(
        (e) => e.title.toLocaleLowerCase("de").includes(q) || (e.venues?.name ?? "").toLocaleLowerCase("de").includes(q),
      );
    });
  }, [groups, query]);

  return (
    <>
      <div className="mt-3">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Gruppen durchsuchen (Titel, Termin, Venue)…"
          className="w-full max-w-sm rounded-lg border border-black/[0.08] bg-white px-3 py-2 text-sm text-neutral-900 placeholder:text-neutral-400 focus:border-[#0071e3] focus:outline-none focus:ring-[3px] focus:ring-[rgba(0,113,227,0.14)]"
        />
      </div>

      {filtered.length === 0 ? (
        <div className="mt-3 border-2 border-dashed border-neutral-300 bg-white px-4 py-8 text-center text-sm text-neutral-400">
          {query ? "Keine Gruppen gefunden." : "Noch keine Gruppen angelegt."}
        </div>
      ) : (
        <div className="mt-3 flex flex-col gap-3">
          {filtered.map((g) => (
            <div key={g.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
              <div className="flex items-center justify-between gap-4">
                <Link href={`/event-groups/${g.id}`} className="font-medium text-neutral-900 hover:underline">
                  {g.title}
                </Link>
                <div className="flex items-center gap-3">
                  <span className="text-xs text-neutral-400">
                    {g.events.length} Termin{g.events.length === 1 ? "" : "e"}
                  </span>
                  <MergeGroupControl
                    groupId={g.id}
                    groupTitle={g.title}
                    groupVenueNames={Array.from(
                      new Set(g.events.map((e) => e.venues?.name).filter((n): n is string => !!n)),
                    )}
                    otherGroups={groups
                      .filter((other) => other.id !== g.id)
                      .map((other) => ({
                        id: other.id,
                        title: other.title,
                        venueNames: Array.from(
                          new Set(other.events.map((e) => e.venues?.name).filter((n): n is string => !!n)),
                        ),
                      }))}
                  />
                  <ConfirmButton
                    action={deleteEventGroup.bind(null, g.id)}
                    confirmMessage={`Gruppe "${g.title}" auflösen? Die Events selbst bleiben erhalten, nur die Verknüpfung wird entfernt.`}
                    label="Auflösen"
                    pendingLabel="Löse auf…"
                    className="text-sm font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
                  />
                </div>
              </div>
              <ul className="mt-2 flex flex-col gap-1 text-sm text-neutral-600">
                {g.events.map((e) => (
                  <li key={e.id}>
                    {e.title} · {formatDate(e.start_datetime)}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}
    </>
  );
}
