"use client";

// Mitwirkende schnell hinzufügen (01.11.2026): ein Suchfeld über Personen und
// Ensembles, jeder Treffer landet per Enter/Klick in einer Liste mit eigenem
// Rollenfeld („Tosca“, „Musikalische Leitung“ …). Ein Klick fügt alle zu den
// ausgewählten Terminen hinzu – statt pro Person ein eigenes Formular.

import { useEffect, useRef, useState, useTransition } from "react";
import { searchEntities, type EntityHit } from "../../events/[id]/program/search-actions";
import { EventChecklist, type ChecklistEvent } from "./event-checklist";
import { addParticipantsBulk } from "./actions";

type Hit = EntityHit & { kind: "person" | "ensemble" };
type Row = Hit & { roleLabel: string };

export function ParticipantBulkAdder({
  groupId,
  events,
  roleSuggestions,
}: {
  groupId: string;
  events: ChecklistEvent[];
  roleSuggestions: string[];
}) {
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<Hit[]>([]);
  const [active, setActive] = useState(0);
  const [rows, setRows] = useState<Row[]>([]);
  const [pending, startTransition] = useTransition();
  const [done, setDone] = useState<string | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const requestId = useRef(0);

  useEffect(() => {
    const q = query.trim();
    const id = ++requestId.current;
    const timer = setTimeout(async () => {
      if (q.length < 2) {
        setHits([]);
        return;
      }
      const [persons, ensembles] = await Promise.all([
        searchEntities("person", q).catch(() => []),
        searchEntities("ensemble", q).catch(() => []),
      ]);
      if (id !== requestId.current) return;
      setHits([
        ...persons.slice(0, 12).map((h) => ({ ...h, kind: "person" as const })),
        ...ensembles.slice(0, 8).map((h) => ({ ...h, kind: "ensemble" as const })),
      ]);
      setActive(0);
    }, 180);
    return () => clearTimeout(timer);
  }, [query]);

  function add(hit: Hit) {
    setRows((prev) => (prev.some((r) => r.id === hit.id) ? prev : [...prev, { ...hit, roleLabel: "" }]));
    setQuery("");
    setHits([]);
    setDone(null);
  }

  function submit() {
    const eventIds = formRef.current
      ? new FormData(formRef.current).getAll("event_ids").map(String)
      : [];
    startTransition(async () => {
      await addParticipantsBulk(
        groupId,
        rows.map((r) => ({
          personId: r.kind === "person" ? r.id : null,
          ensembleId: r.kind === "ensemble" ? r.id : null,
          roleLabel: r.roleLabel || null,
        })),
        eventIds,
      );
      setDone(`${rows.length} hinzugefügt.`);
      setRows([]);
    });
  }

  return (
    <div className="rounded-lg border border-neutral-200 bg-white p-4">
      <p className="text-sm font-semibold text-neutral-900">Mitwirkende hinzufügen</p>
      <p className="mt-1 text-xs text-neutral-500">
        Namen tippen, mit Enter übernehmen, beliebig viele sammeln, Rollen eintragen und alle auf einmal hinzufügen.
      </p>

      <div className="relative mt-3">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "ArrowDown") { e.preventDefault(); setActive((i) => Math.min(i + 1, hits.length - 1)); }
            else if (e.key === "ArrowUp") { e.preventDefault(); setActive((i) => Math.max(i - 1, 0)); }
            else if (e.key === "Enter") { e.preventDefault(); if (hits[active]) add(hits[active]); }
          }}
          placeholder="Person oder Ensemble suchen …"
          aria-label="Person oder Ensemble suchen"
          className="w-full border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-[#2D2A6E]"
        />
        {hits.length > 0 && (
          <ul role="listbox" className="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-xl border border-neutral-200 bg-white py-1 text-sm shadow-lg">
            {hits.map((hit, index) => (
              <li
                key={`${hit.kind}:${hit.id}`}
                role="option"
                aria-selected={index === active}
                onMouseDown={(e) => { e.preventDefault(); add(hit); }}
                onMouseEnter={() => setActive(index)}
                className={`flex cursor-pointer justify-between px-3 py-1.5 ${index === active ? "bg-[#ECEBFA] text-[#2D2A6E]" : "text-neutral-800"}`}
              >
                <span>{hit.label}</span>
                <span className="text-xs text-neutral-400">{hit.kind === "person" ? "Person" : "Ensemble"}</span>
              </li>
            ))}
          </ul>
        )}
      </div>

      {rows.length > 0 && (
        <ul className="mt-3 flex flex-col gap-2">
          {rows.map((row) => (
            <li key={row.id} className="flex items-center gap-2 text-sm">
              <span className="w-44 shrink-0 truncate font-medium text-neutral-900" title={row.label}>{row.label}</span>
              <input
                value={row.roleLabel}
                onChange={(e) => setRows((prev) => prev.map((r) => (r.id === row.id ? { ...r, roleLabel: e.target.value } : r)))}
                placeholder={row.kind === "person" ? "Rolle, z. B. Tosca oder Dirigent:in" : "Funktion (optional)"}
                list="bulk-role-suggestions"
                maxLength={160}
                className="min-w-0 flex-1 border border-neutral-300 px-2 py-1 text-sm"
              />
              <button type="button" onClick={() => setRows((prev) => prev.filter((r) => r.id !== row.id))} aria-label={`${row.label} entfernen`} className="px-1 text-neutral-400 hover:text-neutral-700">
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      <datalist id="bulk-role-suggestions">
        {roleSuggestions.map((r) => <option key={r} value={r} />)}
      </datalist>

      <form ref={formRef} className="mt-3" onSubmit={(e) => { e.preventDefault(); submit(); }}>
        <details>
          <summary className="cursor-pointer text-xs font-medium text-neutral-500">Nur bei bestimmten Terminen …</summary>
          <div className="mt-2">
            <EventChecklist events={events} checkedIds={new Set(events.map((e) => e.id))} />
          </div>
        </details>
        <div className="mt-3 flex items-center justify-between">
          <span className="text-xs text-emerald-700">{done}</span>
          <button type="submit" disabled={rows.length === 0 || pending} className="rounded bg-[#2D2A6E] px-4 py-2 text-sm font-medium text-white disabled:opacity-40">
            {pending ? "Wird hinzugefügt …" : `${rows.length || ""} hinzufügen`}
          </button>
        </div>
      </form>
    </div>
  );
}
