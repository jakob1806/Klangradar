"use server";

import type { DiscoverResult } from "./types";

// Ruft die discover-sources Edge Function auf (gleiches Aufruf-Muster wie
// sources/onboard/actions.ts) — legt nichts direkt an, sondern schlägt
// gefundene Veranstalter nur als entity_candidates zur redaktionellen
// Freigabe vor (siehe backend/supabase/functions/discover-sources/index.ts).
export async function discoverSources(_prevState: DiscoverResult, formData: FormData): Promise<DiscoverResult> {
  const query = String(formData.get("query") ?? "").trim();
  if (!query) return { status: "failed", error: "Bitte einen Suchbegriff eingeben." };

  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  let res: Response;
  try {
    res = await fetch(`${baseUrl}/functions/v1/discover-sources`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey ?? "",
        Authorization: `Bearer ${anonKey ?? ""}`,
        "x-internal-secret": process.env.INTERNAL_FUNCTION_SECRET ?? "",
      },
      body: JSON.stringify({ query }),
    });
  } catch (err) {
    return {
      status: "failed",
      error: `discover-sources nicht erreichbar: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  let body: Record<string, unknown>;
  try {
    body = await res.json();
  } catch {
    return { status: "failed", error: `Unerwartete Antwort (HTTP ${res.status}).` };
  }

  if (!res.ok || body.error) {
    return { status: "failed", error: (body.error as string) ?? `HTTP ${res.status}` };
  }

  return {
    status: "ok",
    query: body.query as string | undefined,
    candidatesFound: body.candidates_found as number | undefined,
    created: body.created as number | undefined,
    skippedKnown: body.skipped_known as number | undefined,
    skippedDuplicatePending: body.skipped_duplicate_pending as number | undefined,
    note: body.note as string | undefined,
  };
}
