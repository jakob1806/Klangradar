"use server";

import type { ProbeResult } from "./types";

// Ruft die probe-source Edge Function auf (gleiches Aufruf-Muster wie
// events/from-url/actions.ts) — reines Read-only-Probing, legt nichts an.
export async function probeSource(_prevState: ProbeResult, formData: FormData): Promise<ProbeResult> {
  const url = String(formData.get("url") ?? "").trim();
  if (!url) return { status: "failed", error: "Bitte eine URL eingeben." };

  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  let res: Response;
  try {
    res = await fetch(`${baseUrl}/functions/v1/probe-source`, {
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
    return { status: "failed", error: `probe-source nicht erreichbar: ${err instanceof Error ? err.message : String(err)}` };
  }

  let body: Record<string, unknown>;
  try {
    body = await res.json();
  } catch {
    return { status: "failed", error: `Unerwartete Antwort (HTTP ${res.status}).` };
  }

  return {
    status: (body.status as ProbeResult["status"]) ?? "failed",
    url,
    recommendedType: (body.recommendedType as ProbeResult["recommendedType"]) ?? null,
    eventsFound: body.eventsFound as number | undefined,
    preview: body.preview as ProbeResult["preview"],
    message: body.message as string | undefined,
    error: body.error as string | undefined,
    errors: body.errors as string[] | undefined,
  };
}
