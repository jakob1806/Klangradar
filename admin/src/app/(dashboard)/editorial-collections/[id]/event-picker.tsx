"use client";

// Textsuche + Hinzufügen statt einer festen Checkbox-Liste (siehe
// membership-editor.tsx bei event-groups) — der Event-Katalog ist hier
// nicht auf eine kleine Programmgruppe begrenzt, sondern der GESAMTE
// Kalender, eine vorgeladene Liste wäre unbrauchbar lang.

import { useState, useTransition } from "react";
import { addEventToCollection, removeEventFromCollection, searchEventsForCollection } from "../actions";

interface SearchResult {
  id: string;
  title: string;
  start_datetime: string;
  venues: { name: string } | null;
}

export interface CollectionEvent {
  id: string;
  title: string;
  start_datetime: string;
  venueName: string | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("de-DE", { dateStyle: "medium" });
}

export function EventPicker({
  collectionId,
  initialEvents,
}: {
  collectionId: string;
  initialEvents: CollectionEvent[];
}) {
  const [events, setEvents] = useState(initialEvents);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const existingIds = new Set(events.map((e) => e.id));

  async function runSearch(value: string) {
    setQuery(value);
    if (value.trim().length < 2) {
      setResults([]);
      return;
    }
    setSearching(true);
    const found = await searchEventsForCollection(value);
    setSearching(false);
    setResults(found);
  }

  function handleAdd(event: SearchResult) {
    setError(null);
    startTransition(async () => {
      try {
        await addEventToCollection(collectionId, event.id);
        setEvents((prev) => [
          ...prev,
          {
            id: event.id,
            title: event.title,
            start_datetime: event.start_datetime,
            venueName: event.venues?.name ?? null,
          },
        ]);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Hinzufügen fehlgeschlagen.");
      }
    });
  }

  function handleRemove(eventId: string) {
    setError(null);
    startTransition(async () => {
      try {
        await removeEventFromCollection(collectionId, eventId);
        setEvents((prev) => prev.filter((e) => e.id !== eventId));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Entfernen fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="max-w-xl">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">
        Veranstaltungen in dieser Sammlung ({events.length})
      </p>
      <div className="mt-2 flex flex-col gap-2">
        {events.map((e) => (
          <div
            key={e.id}
            className="flex items-center justify-between rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm"
          >
            <span>
              {e.title}{" "}
              <span className="text-neutral-400">
                — {formatDate(e.start_datetime)}
                {e.venueName ? ` · ${e.venueName}` : ""}
              </span>
            </span>
            <button
              type="button"
              disabled={pending}
              onClick={() => handleRemove(e.id)}
              className="text-xs font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
            >
              Entfernen
            </button>
          </div>
        ))}
        {events.length === 0 && (
          <p className="text-sm text-neutral-400">Noch keine Veranstaltungen zugeordnet.</p>
        )}
      </div>

      <p className="mt-6 text-xs font-medium uppercase tracking-wide text-neutral-400">Veranstaltung hinzufügen</p>
      <input
        value={query}
        onChange={(e) => runSearch(e.target.value)}
        placeholder="Titel suchen…"
        className="mt-2 w-full rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
      />
      {searching && <p className="mt-2 text-xs text-neutral-400">Suche…</p>}
      {results.length > 0 && (
        <div className="mt-2 flex flex-col gap-1 rounded-md border border-neutral-200 bg-white">
          {results.map((r) => (
            <div key={r.id} className="flex items-center justify-between border-b border-neutral-100 px-3 py-2 text-sm last:border-b-0">
              <span>
                {r.title}{" "}
                <span className="text-neutral-400">
                  — {formatDate(r.start_datetime)}
                  {r.venues?.name ? ` · ${r.venues.name}` : ""}
                </span>
              </span>
              <button
                type="button"
                disabled={pending || existingIds.has(r.id)}
                onClick={() => handleAdd(r)}
                className="text-xs font-medium text-neutral-700 hover:text-neutral-900 disabled:opacity-40"
              >
                {existingIds.has(r.id) ? "Bereits dabei" : "Hinzufügen"}
              </button>
            </div>
          ))}
        </div>
      )}
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
    </div>
  );
}
