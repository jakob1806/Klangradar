"use client";

import { useState, useTransition } from "react";
import { enrichEntity, type EnrichEntityType, type EnrichResult } from "@/lib/enrich-actions";

const FIELD_LABEL: Record<string, string> = {
  birth_date: "Geburtsdatum",
  death_date: "Sterbedatum",
  instrument: "Instrument",
  roles: "Rolle(n)",
  biography_de: "Biografie",
  nationality: "Nationalität",
  website_url: "Website",
  description_de: "Beschreibung",
  history_de: "Geschichte",
  capacity: "Kapazität",
  founded_year: "Gründungsjahr",
  member_count: "Mitgliederzahl",
  program_notes_de: "Programmtext",
  duration_minutes: "Dauer (Min.)",
};

function formatFieldValue(value: unknown): string {
  if (Array.isArray(value)) return value.join(", ");
  if (typeof value === "string" && value.length > 80) return `${value.slice(0, 80)}…`;
  return String(value);
}

export function AiEnrichButton({ entityType, entityId }: { entityType: EnrichEntityType; entityId: string }) {
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<EnrichResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    setResult(null);
    startTransition(async () => {
      try {
        const r = await enrichEntity(entityType, entityId);
        setResult(r);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Anreicherung fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="flex flex-col items-start gap-2">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="type-label rounded-none border-2 border-[#171717] bg-white px-3 py-1.5 !text-[#171717] hover:bg-[#171717] hover:!text-white disabled:opacity-50"
      >
        {pending ? "Prüfe & ergänze…" : "Prüfen & ergänzen (KI)"}
      </button>
      {error && <p className="text-xs text-red-600">{error}</p>}
      {result && (
        <div
          className={`max-w-md border-2 px-3 py-2 text-xs ${
            result.status === "filled"
              ? "border-green-700 bg-green-50 text-green-900"
              : result.status === "error"
                ? "border-red-700 bg-red-50 text-red-900"
                : "border-neutral-300 bg-neutral-50 text-neutral-600"
          }`}
        >
          <p className="font-medium">{result.diagnosis}</p>
          {result.filledFields.length > 0 && (
            <ul className="mt-1.5 flex flex-col gap-0.5">
              {result.filledFields.map((f) => (
                <li key={f.field}>
                  <span className="font-medium">{FIELD_LABEL[f.field] ?? f.field}:</span> {formatFieldValue(f.value)}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
