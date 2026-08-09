"use client";

// Eigenständiger Einstieg für "Bio-Recherche" als Tab in der Sidebar
// (Nutzerwunsch: "Bio recherche soll auch einen eigenen Tab bekommen wie
// bilder recherchieren") — bisher war /bio-research NUR über eine
// Checkbox-Auswahl auf den Personen-/Venues-/Ensembles-Listenseiten
// erreichbar (BioResearchBar in bio-select.tsx, übergibt ids= in der URL).
// Dieser Picker bietet dieselbe Auswahl-dann-Workflow-Zweiteilung direkt
// hier, exakt nach dem Vorbild von image-research-client.tsx.

import { useState } from "react";
import Link from "next/link";
import { BioResearchWorkflow, type BioWorkflowEntity } from "./bio-research-workflow";
import type { BioEntityType } from "./actions";

export interface BioEntityOption {
  id: string;
  name: string;
  hasBio: boolean;
}

export function BioResearchPicker({
  entityType,
  entities,
}: {
  entityType: BioEntityType;
  entities: BioEntityOption[];
}) {
  const [phase, setPhase] = useState<"select" | "workflow">("select");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [filter, setFilter] = useState("");
  const [onlyMissing, setOnlyMissing] = useState(false);

  const visible = entities.filter((e) => {
    if (onlyMissing && e.hasBio) return false;
    if (filter && !e.name.toLowerCase().includes(filter.toLowerCase())) return false;
    return true;
  });

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  if (phase === "workflow") {
    const chosen: BioWorkflowEntity[] = entities
      .filter((e) => selected.has(e.id))
      .map((e) => ({ id: e.id, name: e.name, currentBio: null }));
    return (
      <div>
        <button
          type="button"
          onClick={() => setPhase("select")}
          className="text-sm text-neutral-500 hover:text-neutral-700"
        >
          ← Zurück zur Auswahl
        </button>
        <div className="mt-4">
          <BioResearchWorkflow entityType={entityType} entities={chosen} />
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3">
        <input
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Name filtern…"
          className="border border-neutral-300 px-3 py-1.5 text-sm outline-none focus:border-[#171717]"
        />
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          <input
            type="checkbox"
            checked={onlyMissing}
            onChange={(e) => setOnlyMissing(e.target.checked)}
            className="h-4 w-4 rounded border-neutral-300"
          />
          Nur ohne Bio
        </label>
        <button
          type="button"
          onClick={() => setSelected(new Set(visible.map((e) => e.id)))}
          className="text-xs font-medium text-neutral-500 underline hover:text-neutral-800"
        >
          Alle sichtbaren auswählen ({visible.length})
        </button>
        {selected.size > 0 && (
          <button
            type="button"
            onClick={() => setSelected(new Set())}
            className="text-xs font-medium text-neutral-500 underline hover:text-neutral-800"
          >
            Auswahl leeren
          </button>
        )}
        {selected.size > 0 && (
          <button
            type="button"
            onClick={() => setPhase("workflow")}
            className="ml-auto border-2 border-[#171717] bg-[#171717] px-4 py-2 type-label !text-white hover:bg-white hover:!text-[#171717]"
          >
            {selected.size} ausgewählt — Bios recherchieren →
          </button>
        )}
      </div>

      <div className="mt-4 max-h-[60vh] overflow-y-auto border-2 border-[#171717] bg-white">
        {visible.map((e) => (
          <label
            key={e.id}
            className="flex items-center gap-3 border-b border-neutral-100 px-4 py-2.5 text-sm last:border-b-0 hover:bg-neutral-50"
          >
            <input
              type="checkbox"
              checked={selected.has(e.id)}
              onChange={() => toggle(e.id)}
              className="h-4 w-4 rounded border-neutral-300"
            />
            <span className="flex-1 text-neutral-900">{e.name}</span>
            <span
              className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${
                e.hasBio ? "bg-blue-50 text-blue-700" : "bg-neutral-100 text-neutral-400"
              }`}
            >
              {e.hasBio ? "Bio vorhanden" : "Keine Bio"}
            </span>
          </label>
        ))}
        {visible.length === 0 && <p className="px-4 py-6 text-sm text-neutral-400">Keine Treffer.</p>}
      </div>
    </div>
  );
}

export function EntityTypeTabs({ entityType }: { entityType: BioEntityType }) {
  const labels: Record<BioEntityType, string> = {
    person: "Personen",
    venue: "Venues",
    ensemble: "Ensembles",
  };
  return (
    <div className="mt-4 flex gap-2">
      {(Object.keys(labels) as BioEntityType[]).map((t) => (
        <Link
          key={t}
          href={`/bio-research?type=${t}`}
          className={`px-3 py-1.5 type-label ${
            t === entityType
              ? "border-2 border-[#171717] bg-[#171717] !text-white"
              : "border-2 border-transparent !text-neutral-500 hover:!text-[#171717]"
          }`}
        >
          {labels[t]}
        </Link>
      ))}
    </div>
  );
}
