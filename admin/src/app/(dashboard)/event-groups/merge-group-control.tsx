"use client";

import { useState, useTransition } from "react";
import { mergeEventGroups } from "./actions";

// Nutzeranfrage: "eventgruppen soll man auch zusammenführen können" —
// dezenter Textlink analog zu MembershipEditor (kein Dauerbestandteil der
// Karte), blendet bei Klick eine Auswahl aller ANDEREN Gruppen ein.
//
// Nutzeranfrage: "bitte auch warnung, falls man events mit zwar dem
// gleichen programm aber einem unterschiedlichen standort zusammenführen
// will" — die automatischen Vorschläge (suggestGroupMerges) verlangen
// bereits einen gemeinsamen Standort, aber dieser manuelle Weg hier erlaubt
// bewusst JEDE Zielgruppe (z.B. um zwei wirklich unabhängige Serien absichtlich
// zusammenzulegen) — nur eine Warnung statt einer Sperre, kein Blocker.
export function MergeGroupControl({
  groupId,
  groupTitle,
  groupVenueNames,
  otherGroups,
}: {
  groupId: string;
  groupTitle: string;
  groupVenueNames: string[];
  otherGroups: { id: string; title: string; venueNames: string[] }[];
}) {
  const [open, setOpen] = useState(false);
  const [targetId, setTargetId] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  if (otherGroups.length === 0) return null;

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="text-xs font-medium text-neutral-500 hover:text-neutral-800"
      >
        Zusammenführen
      </button>
    );
  }

  const target = otherGroups.find((g) => g.id === targetId);
  const targetTitle = target?.title;
  const sharesVenue =
    groupVenueNames.length === 0 ||
    !target ||
    target.venueNames.length === 0 ||
    target.venueNames.some((v) => groupVenueNames.includes(v));

  return (
    <div className="flex flex-col items-end gap-1.5">
      <div className="flex items-center gap-2">
        <select
          value={targetId}
          onChange={(e) => {
            setTargetId(e.target.value);
            setConfirming(false);
          }}
          className="rounded-md border border-neutral-300 bg-white px-2 py-1 text-xs text-neutral-700"
        >
          <option value="">In Gruppe wählen…</option>
          {otherGroups.map((g) => (
            <option key={g.id} value={g.id}>
              {g.title}
            </option>
          ))}
        </select>
        {confirming ? (
          <span className="text-xs text-neutral-600">Sicher?</span>
        ) : null}
        <button
          type="button"
          disabled={!targetId || pending}
          onClick={() => {
            if (!confirming) {
              setConfirming(true);
              return;
            }
            setError(null);
            startTransition(async () => {
              try {
                await mergeEventGroups(groupId, targetId);
                setOpen(false);
                setConfirming(false);
              } catch (err) {
                setError(err instanceof Error ? err.message : "Zusammenführen fehlgeschlagen.");
              }
            });
          }}
          className="rounded-md bg-neutral-900 px-2.5 py-1 text-xs font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
        >
          {pending ? "Führe zusammen…" : "Zusammenführen"}
        </button>
        <button
          type="button"
          onClick={() => {
            setOpen(false);
            setConfirming(false);
            setTargetId("");
          }}
          className="text-xs font-medium text-neutral-500 hover:text-neutral-800"
        >
          Abbrechen
        </button>
      </div>
      {targetTitle && !sharesVenue && (
        <p className="max-w-xs text-right text-xs text-amber-700">
          ⚠️ „{groupTitle}“ ({groupVenueNames.join(", ") || "kein Standort hinterlegt"}) und „{targetTitle}“ (
          {target!.venueNames.join(", ") || "kein Standort hinterlegt"}) haben keinen gemeinsamen Standort — evtl.
          doch keine gemeinsame Produktion?
        </p>
      )}
      {confirming && targetTitle && (
        <p className="max-w-xs text-right text-xs text-neutral-500">
          Alle Termine von „{groupTitle}“ wandern zu „{targetTitle}“, „{groupTitle}“ wird danach gelöscht.
        </p>
      )}
      {error && <p className="max-w-xs text-right text-xs text-red-600">{error}</p>}
    </div>
  );
}
