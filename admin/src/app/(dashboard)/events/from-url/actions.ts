"use server";

import { revalidatePath } from "next/cache";
import type { ExtractResult } from "./types";

// Ruft die extract-event-from-url Edge Function direkt auf (gleiches Muster
// wie runSourceNow in ../../sources/actions.ts) — anders als dort wird das
// Ergebnis hier aber zurückgegeben statt nur revalidiert, weil der Admin bei
// einer neuen, weniger vorhersagbaren Aktion (beliebige URL statt einer
// bereits getesteten Quelle) eine direkte Rückmeldung braucht.
export async function extractEventsFromUrl(
  _prevState: ExtractResult,
  formData: FormData,
): Promise<ExtractResult> {
  const url = String(formData.get("url") ?? "").trim();
  if (!url) {
    return { status: "failed", error: "Bitte eine URL eingeben." };
  }

  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  let res: Response;
  try {
    res = await fetch(`${baseUrl}/functions/v1/extract-event-from-url`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey ?? "",
        Authorization: `Bearer ${anonKey ?? ""}`,
        "x-internal-secret": process.env.INTERNAL_FUNCTION_SECRET ?? "",
      },
      body: JSON.stringify({ url }),
    });
  } catch (err) {
    return {
      status: "failed",
      error: `extract-event-from-url nicht erreichbar: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  let body: Record<string, unknown>;
  try {
    body = await res.json();
  } catch {
    return { status: "failed", error: `Unerwartete Antwort (HTTP ${res.status}).` };
  }

  if (body.status !== "success") {
    return {
      status: "failed",
      error: typeof body.error === "string" ? body.error : "Extraktion fehlgeschlagen.",
      extractionMethod: body.extraction_method as "schema_org" | "llm" | undefined,
      errors: Array.isArray(body.details)
        ? (body.details as string[])
        : Array.isArray(body.errors)
        ? (body.errors as string[])
        : undefined,
    };
  }

  revalidatePath("/events");

  return {
    status: "success",
    extractionMethod: body.extraction_method as "schema_org" | "llm",
    eventsFound: body.events_found as number,
    eventsCreated: body.events_created as number,
    eventsUpdated: body.events_updated as number,
    eventsFlaggedForReview: body.events_flagged_for_review as number,
    results: body.results as Array<{ title: string; outcome: string; error?: string }>,
    errors: Array.isArray(body.errors) && body.errors.length > 0 ? (body.errors as string[]) : undefined,
  };
}
