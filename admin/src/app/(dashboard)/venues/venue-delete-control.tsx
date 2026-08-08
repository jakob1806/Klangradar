"use client";

// Analogon zu ensembles/ensemble-delete-control.tsx: erst zeigen, was noch
// verknüpft ist (Veranstaltungen/Heimat-Ensembles/Quellen/Kandidaten),
// dann erst löschen lassen statt zu blockieren. Anders als bei Ensembles/
// Personen werden verknüpfte Veranstaltungen beim Löschen NICHT entfernt,
// nur die Ortszuordnung — siehe detachVenueReferences in actions.ts.

import Link from "next/link";
import { useState, useTransition } from "react";
import { deleteVenue, getVenueDeleteInfo, type VenueDeleteInfo } from "./actions";

type ControlState =
  | { phase: "idle" }
  | { phase: "loading" }
  | { phase: "confirm-simple" }
  | { phase: "confirm-cascade"; info: VenueDeleteInfo }
  | { phase: "error"; message: string };

const MAX_LISTED = 8;

export function VenueDeleteControl({
  venueId,
  venueName,
}: {
  venueId: string;
  venueName: string;
}) {
  const [state, setState] = useState<ControlState>({ phase: "idle" });
  const [pending, startTransition] = useTransition();

  async function handleStart() {
    setState({ phase: "loading" });
    try {
      const info = await getVenueDeleteInfo(venueId);
      const hasLinks =
        info.events.length > 0 || info.ensembles.length > 0 || info.sources.length > 0 || info.candidateCount > 0;
      setState(hasLinks ? { phase: "confirm-cascade", info } : { phase: "confirm-simple" });
    } catch (e) {
      setState({ phase: "error", message: e instanceof Error ? e.message : "Verknüpfungen konnten nicht geladen werden." });
    }
  }

  function handleDelete() {
    startTransition(async () => {
      try {
        await deleteVenue(venueId);
      } catch (e) {
        setState({ phase: "error", message: e instanceof Error ? e.message : "Löschen fehlgeschlagen." });
      }
    });
  }

  if (state.phase === "idle") {
    return (
      <button type="button" onClick={handleStart} className="text-sm font-medium text-red-600 hover:text-red-800">
        Löschen
      </button>
    );
  }

  if (state.phase === "loading") {
    return <span className="text-sm text-neutral-400">Prüfe Verknüpfungen…</span>;
  }

  if (state.phase === "error") {
    return (
      <span className="inline-flex flex-col items-end gap-1">
        <span className="max-w-xs text-right text-xs text-red-600">{state.message}</span>
        <button
          type="button"
          onClick={() => setState({ phase: "idle" })}
          className="text-xs font-medium text-neutral-500 underline hover:text-neutral-700"
        >
          Erneut versuchen
        </button>
      </span>
    );
  }

  if (state.phase === "confirm-simple") {
    return (
      <span className="inline-flex items-center gap-2 text-sm">
        <span className="text-neutral-600">„{venueName}“ wirklich löschen?</span>
        <button
          type="button"
          disabled={pending}
          onClick={handleDelete}
          className="font-medium text-red-700 hover:text-red-900 disabled:opacity-50"
        >
          {pending ? "Lösche…" : "Ja, sicher"}
        </button>
        <button
          type="button"
          disabled={pending}
          onClick={() => setState({ phase: "idle" })}
          className="font-medium text-neutral-500 hover:text-neutral-700 disabled:opacity-50"
        >
          Abbrechen
        </button>
      </span>
    );
  }

  const { info } = state;
  return (
    <div className="max-w-sm rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm">
      <p className="font-medium text-amber-900">„{venueName}“ ist noch verknüpft:</p>

      {info.events.length > 0 && (
        <div className="mt-2">
          <p className="text-xs font-medium uppercase tracking-wide text-amber-700">
            {info.events.length} Veranstaltung{info.events.length === 1 ? "" : "en"}
          </p>
          <ul className="mt-1 flex flex-col gap-0.5">
            {info.events.slice(0, MAX_LISTED).map((e) => (
              <li key={e.id}>
                <Link href={`/events/${e.id}`} target="_blank" className="text-amber-800 underline hover:text-amber-950">
                  {e.title}
                </Link>
              </li>
            ))}
            {info.events.length > MAX_LISTED && (
              <li className="text-amber-700">… und {info.events.length - MAX_LISTED} weitere</li>
            )}
          </ul>
        </div>
      )}

      {info.ensembles.length > 0 && (
        <div className="mt-2">
          <p className="text-xs font-medium uppercase tracking-wide text-amber-700">
            {info.ensembles.length} Ensemble(s) mit dieser Heimat-Venue
          </p>
          <ul className="mt-1 flex flex-col gap-0.5">
            {info.ensembles.map((e) => (
              <li key={e.id}>
                <Link href={`/ensembles/${e.id}`} target="_blank" className="text-amber-800 underline hover:text-amber-950">
                  {e.name}
                </Link>
              </li>
            ))}
          </ul>
        </div>
      )}

      {info.sources.length > 0 && (
        <div className="mt-2">
          <p className="text-xs font-medium uppercase tracking-wide text-amber-700">
            {info.sources.length} Datenquelle{info.sources.length === 1 ? "" : "n"}
          </p>
          <ul className="mt-1 flex flex-col gap-0.5">
            {info.sources.map((s) => (
              <li key={s.id}>
                <Link href={`/sources/${s.id}`} target="_blank" className="text-amber-800 underline hover:text-amber-950">
                  {s.name}
                </Link>
              </li>
            ))}
          </ul>
        </div>
      )}

      {info.candidateCount > 0 && (
        <p className="mt-2 text-xs text-amber-700">
          {info.candidateCount} Entity-Kandidat(en) verweisen ebenfalls darauf.
        </p>
      )}

      <p className="mt-3 text-xs text-amber-800">
        Beim Löschen verlieren die genannten Veranstaltungen/Ensembles/Quellen/Kandidaten nur die Ortszuordnung
        (venue_id = leer) — sie werden nicht gelöscht.
      </p>

      <div className="mt-3 flex items-center gap-3">
        <button
          type="button"
          disabled={pending}
          onClick={handleDelete}
          className="rounded-md bg-red-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-red-700 disabled:opacity-50"
        >
          {pending ? "Lösche…" : "Trotzdem löschen"}
        </button>
        <button
          type="button"
          disabled={pending}
          onClick={() => setState({ phase: "idle" })}
          className="text-xs font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
        >
          Abbrechen
        </button>
      </div>
    </div>
  );
}
