"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type BioEntityType = "person" | "ensemble" | "venue";

const TABLE_FOR_TYPE: Record<BioEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  venue: "venues",
};

const BIO_COLUMN_FOR_TYPE: Record<BioEntityType, string> = {
  person: "biography_de",
  ensemble: "description_de",
  venue: "description_de",
};

export interface BioResearchOutcome {
  found: boolean;
  biography?: string;
  sourceUrl?: string;
  source?: "wikipedia" | "ai_knowledge";
  error?: string;
}

/** Ruft die research-entity-bio Edge Function für EINE Entität auf — der
 * sequentielle Ein-nach-dem-anderen-Ablauf lebt bewusst im Client
 * (bio-research-workflow.tsx), diese Action ist nur der einzelne
 * Recherche-Schritt, damit ein einzelner langsamer/fehlschlagender Aufruf
 * nicht den ganzen Batch blockiert. */
export async function researchBio(entityType: BioEntityType, entityId: string): Promise<BioResearchOutcome> {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  let res: Response;
  try {
    res = await fetch(`${baseUrl}/functions/v1/research-entity-bio`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey ?? "",
        Authorization: `Bearer ${anonKey ?? ""}`,
        "x-internal-secret": process.env.INTERNAL_FUNCTION_SECRET ?? "",
      },
      body: JSON.stringify({ entityType, entityId }),
      // 30s war zu knapp: researchBiography() kann bis zu ZWEI KI-Aufrufe
      // sequenziell brauchen (erst Wikipedia-Zusammenfassung, bei nicht
      // ausreichender Konfidenz zusätzlich der Eigenwissen-Fallback), jeder
      // einzelne mit einer bis zu 3-stufigen Provider-Fallback-Kette à 20s
      // Timeout (_shared/ai/router.ts) — im ungünstigen Fall (mehrere
      // Provider gerade langsam/ausgefallen) reichen 30s oft nicht, obwohl
      // das Backend kurz danach noch ein Ergebnis geliefert hätte. Live
      // gemessen: ein einzelner Lauf brauchte bereits ~19s im Normalfall.
      signal: AbortSignal.timeout(90_000),
    });
  } catch (err) {
    return { found: false, error: err instanceof Error ? err.message : String(err) };
  }

  let body: Record<string, unknown>;
  try {
    body = await res.json();
  } catch {
    return { found: false, error: `Unerwartete Antwort (HTTP ${res.status}).` };
  }

  if (!res.ok || body.error) {
    return { found: false, error: (body.error as string) ?? `HTTP ${res.status}` };
  }

  return {
    found: Boolean(body.found),
    biography: typeof body.biography === "string" ? body.biography : undefined,
    sourceUrl: typeof body.sourceUrl === "string" ? body.sourceUrl : undefined,
    source: body.source === "ai_knowledge" ? "ai_knowledge" : body.source === "wikipedia" ? "wikipedia" : undefined,
  };
}

/** Übernimmt den (ggf. von der Redaktion bearbeiteten) Text — überschreibt
 * eine bestehende Bio nur, wenn der Text sich tatsächlich geändert hat
 * (Übernehmen-Klick impliziert das ohnehin, aber so bleibt die Funktion
 * auch für ein direktes "leeren Text speichern" sauber). */
export async function saveBio(entityType: BioEntityType, entityId: string, biography: string) {
  const supabase = await createClient();
  const table = TABLE_FOR_TYPE[entityType];
  const column = BIO_COLUMN_FOR_TYPE[entityType];

  const { error } = await supabase
    .from(table)
    .update({ [column]: biography.trim() || null })
    .eq("id", entityId);
  if (error) throw new Error(error.message);

  revalidatePath(entityType === "person" ? "/persons" : entityType === "ensemble" ? "/ensembles" : "/venues");
}
