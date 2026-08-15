"use client";

// Eigenständiger Einstieg für "Bio-Recherche" als Tab in der Sidebar
// (Nutzerwunsch: "Bio recherche soll auch einen eigenen Tab bekommen wie
// bilder recherchieren") — bisher war /bio-research NUR über eine
// Checkbox-Auswahl auf den Personen-/Venues-/Ensembles-Listenseiten
// erreichbar (BioResearchBar in bio-select.tsx, übergibt ids= in der URL).
// Dieser Picker bietet dieselbe Auswahl-dann-Workflow-Zweiteilung direkt
// hier, exakt nach dem Vorbild von image-research-client.tsx.

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { BioResearchWorkflow, type BioWorkflowEntity } from "./bio-research-workflow";
import type { BioEntityType } from "./actions";

export interface BioEntityOption {
  id: string;
  name: string;
  hasBio: boolean;
  bioStatus?: "pending" | "processing" | "generated" | "not_known" | "error";
  hasImage?: boolean;
  imageSearchNote?: string | null;
}

export function BioResearchPicker({
  entityType,
  entities,
}: {
  entityType: BioEntityType;
  entities: BioEntityOption[];
}) {
  const router = useRouter();
  const [phase, setPhase] = useState<"select" | "workflow">("select");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [filter, setFilter] = useState("");
  const [onlyMissing, setOnlyMissing] = useState(false);

  // Der Personen-Tab ist nun eine Live-Übersicht der automatischen Queue.
  // Während er geöffnet ist, werden neu fertiggestellte Biografien ohne
  // manuelles Neuladen sichtbar.
  useEffect(() => {
    if (entityType !== "person") return;
    const timer = window.setInterval(() => router.refresh(), 20_000);
    return () => window.clearInterval(timer);
  }, [entityType, router]);

  const visible = entities.filter((e) => {
    if (onlyMissing && e.hasBio) return false;
    if (filter && !e.name.toLowerCase().includes(filter.toLowerCase())) return false;
    return true;
  });

  if (entityType === "person") {
    const withBio = entities.filter((entity) => entity.hasBio).length;
    const withImage = entities.filter((entity) => entity.hasImage).length;
    const processing = entities.filter((entity) =>
      !entity.hasBio && ["pending", "processing", "error", "not_known"].includes(entity.bioStatus ?? "pending")
    ).length;

    return (
      <div>
        <div className="grid gap-3 sm:grid-cols-3">
          <SummaryCard label="Biografien vorhanden" value={withBio} total={entities.length} />
          <SummaryCard label="Automatisch in Bearbeitung" value={processing} total={entities.length} />
          <SummaryCard label="Profilbilder vorhanden" value={withImage} total={entities.length} />
        </div>

        <div className="mt-5 flex flex-wrap items-center gap-3">
          <input
            value={filter}
            onChange={(event) => setFilter(event.target.value)}
            placeholder="Person suchen…"
            className="min-w-64 rounded-lg border border-black/10 px-3 py-2 text-sm outline-none focus:border-[#0071e3]"
          />
          <label className="flex items-center gap-2 text-sm text-neutral-600">
            <input
              type="checkbox"
              checked={onlyMissing}
              onChange={(event) => setOnlyMissing(event.target.checked)}
              className="h-4 w-4 rounded border-neutral-300"
            />
            Nur ohne Biografie
          </label>
          <span className="ml-auto text-xs text-neutral-400">Aktualisiert sich alle 20 Sekunden</span>
        </div>

        <div className="mt-4 max-h-[62vh] overflow-y-auto rounded-xl border border-black/[0.06] bg-white shadow-sm">
          {visible.map((entity) => (
            <Link
              key={entity.id}
              href={`/persons/${entity.id}`}
              className="flex items-center gap-3 border-b border-neutral-100 px-4 py-3 text-sm last:border-b-0 hover:bg-neutral-50"
            >
              <span className="min-w-0 flex-1 truncate font-medium text-neutral-900">{entity.name}</span>
              <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${bioStatusClass(entity)}`}>
                {bioStatusLabel(entity)}
              </span>
              <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${
                entity.hasImage ? "bg-emerald-50 text-emerald-700" : "bg-neutral-100 text-neutral-500"
              }`} title={entity.imageSearchNote ?? undefined}>
                {entity.hasImage ? "Bild vorhanden" : entity.imageSearchNote?.includes("wartet") ? "Bildkandidat" : "Bildsuche läuft"}
              </span>
              <span aria-hidden className="text-neutral-300">›</span>
            </Link>
          ))}
          {visible.length === 0 && <p className="px-4 py-8 text-center text-sm text-neutral-400">Keine Treffer.</p>}
        </div>
      </div>
    );
  }

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
          className="rounded-lg border border-black/10 px-3 py-1.5 text-sm outline-none focus:border-[#0071e3]"
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
            className="ml-auto rounded-lg bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
          >
            {selected.size} ausgewählt — Bios recherchieren →
          </button>
        )}
      </div>

      <div className="mt-4 max-h-[60vh] overflow-y-auto rounded-xl border border-black/[0.06] bg-white shadow-sm">
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

function SummaryCard({ label, value, total }: { label: string; value: number; total: number }) {
  return (
    <div className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">{label}</p>
      <p className="mt-1 text-2xl font-semibold tracking-tight text-neutral-900">
        {value}<span className="ml-1 text-sm font-normal text-neutral-400">/ {total}</span>
      </p>
    </div>
  );
}

function bioStatusLabel(entity: BioEntityOption) {
  if (entity.hasBio) return "Bio vorhanden";
  if (entity.bioStatus === "processing") return "KI recherchiert";
  if (entity.bioStatus === "error") return "Wird erneut versucht";
  if (entity.bioStatus === "not_known") return "Weitere Recherche geplant";
  return "In Warteschlange";
}

function bioStatusClass(entity: BioEntityOption) {
  if (entity.hasBio) return "bg-blue-50 text-blue-700";
  if (entity.bioStatus === "processing") return "bg-violet-50 text-violet-700";
  if (entity.bioStatus === "error") return "bg-amber-50 text-amber-700";
  return "bg-neutral-100 text-neutral-500";
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
              ? "rounded-lg bg-[#0071e3] !text-white"
              : "rounded-lg border-2 border-transparent !text-neutral-500 hover:!text-[#1d1d1f] hover:bg-black/[0.04]"
          }`}
        >
          {labels[t]}
        </Link>
      ))}
    </div>
  );
}
