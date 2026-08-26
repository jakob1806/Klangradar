"use server";

// Gemeinsame Server Action für den "Prüfen & Ergänzen"-Button auf Venue-/
// Personen-/Ensemble-/Event-Detailseiten — Nutzerwunsch: "bei jeder venue,
// person, ensemble und veranstaltung fehlt nach wie vor der button, dass
// mithilfe von KI daten automatisch ausgefüllt werden können. z.b.
// Geburtsdatum, sterbedatum, rolle, instrument, website, programmtext,
// dauer der veranstaltung usw." Ruft die neue, gezielte
// enrich-entity-oncall Edge Function für GENAU eine Entität auf (anders als
// die bestehenden enrich-person-profile/enrich-venue-details/enrich-
// ensemble-profile/enrich-event-references-Functions, die nur als
// Batch-Cron mit selbstgewählten Kandidaten laufen).

import { revalidatePath } from "next/cache";

export type EnrichEntityType = "person" | "venue" | "ensemble" | "event";

const REVALIDATE_PATH: Record<EnrichEntityType, string> = {
  person: "/persons",
  venue: "/venues",
  ensemble: "/ensembles",
  event: "/events",
};

export interface EnrichResult {
  status: "filled" | "no_change" | "error";
  diagnosis: string;
  filledFields: { field: string; value: unknown }[];
}

function functionsUrl(path: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${path}`;
}

export async function enrichEntity(entityType: EnrichEntityType, entityId: string): Promise<EnrichResult> {
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  const res = await fetch(functionsUrl("enrich-entity-oncall"), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "x-internal-secret": process.env.INTERNAL_FUNCTION_SECRET ?? "",
    },
    body: JSON.stringify({ entityType, entityId }),
    // Websuche-Fallback + KI-Aufruf können zusammen deutlich länger als
    // einen einzelnen Seitenabruf brauchen (siehe auto-fix-content-report's
    // gleiches Timeout-Problem) — 60s statt Next.js' Default.
    signal: AbortSignal.timeout(60_000),
  });

  const data = await res.json().catch(() => null);
  if (!res.ok || !data) {
    throw new Error(data?.error ?? `Anreicherung fehlgeschlagen (HTTP ${res.status}).`);
  }

  if (data.status === "filled") {
    revalidatePath(`${REVALIDATE_PATH[entityType]}/${entityId}`);
  }

  return {
    status: data.status,
    diagnosis: data.diagnosis,
    filledFields: data.filledFields ?? [],
  };
}
