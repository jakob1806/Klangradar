"use server";

import { revalidatePath } from "next/cache";

export type ImageEntityType = "person" | "venue" | "ensemble" | "event";

export interface ImageSearchResult {
  found: boolean;
  imageUrl?: string;
  sourcePageUrl?: string;
  sourceName?: string;
  matchReason?: string;
  suggestedLicenseStatus?: "confirmed_free" | "confirmed_licensed";
  error?: string;
}

export interface ImageCommitResult {
  committed: boolean;
  imageId?: string;
  error?: string;
}

function functionsUrl(path: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${path}`;
}

function authHeaders() {
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  return {
    "Content-Type": "application/json",
    apikey: anonKey,
    Authorization: `Bearer ${anonKey}`,
  };
}

/** Ein Rechercheschritt für EINE Entität — analog zu bio-research/actions.ts
 * researchBio(). Mit sourceUrl: extrahiert nur das Bild dieser einen Seite
 * (Nutzerwunsch: "man schickt einen Link... und die KI das Bild
 * heraussucht"). Ohne: automatische Recherche nach Entitätstyp. */
export async function searchEntityImage(
  entityType: ImageEntityType,
  entityId: string,
  sourceUrl?: string,
): Promise<ImageSearchResult> {
  let res: Response;
  try {
    res = await fetch(functionsUrl("research-entity-image"), {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({ mode: "search", entityType, entityId, sourceUrl }),
      signal: AbortSignal.timeout(30_000),
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
  if (!res.ok && !body.found) return { found: false, error: (body.error as string) ?? `HTTP ${res.status}` };
  return body as unknown as ImageSearchResult;
}

/** Übernimmt ein zuvor per searchEntityImage gefundenes (oder manuell
 * verlinktes) Bild — schreibt über die Edge Function (ensureCoverImage,
 * braucht ImageMagick-WASM, das gibt es nur dort) tatsächlich in die
 * images-Tabelle. needsReview ist serverseitig immer false: ein Mensch hat
 * das Bild in DIESEM Workflow gerade live gesehen. */
export async function commitEntityImage(
  entityType: ImageEntityType,
  entityId: string,
  input: {
    sourceUrl?: string;
    sourceName?: string;
    sourcePageUrl?: string;
    matchReason?: string;
    licenseStatus: "confirmed_free" | "confirmed_licensed";
  },
): Promise<ImageCommitResult> {
  let res: Response;
  try {
    res = await fetch(functionsUrl("research-entity-image"), {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({ mode: "commit", entityType, entityId, ...input }),
      signal: AbortSignal.timeout(60_000),
    });
  } catch (err) {
    return { committed: false, error: err instanceof Error ? err.message : String(err) };
  }

  let body: Record<string, unknown>;
  try {
    body = await res.json();
  } catch {
    return { committed: false, error: `Unerwartete Antwort (HTTP ${res.status}).` };
  }
  if (!res.ok) return { committed: false, error: (body.error as string) ?? `HTTP ${res.status}` };
  if (body.committed) revalidatePath("/media");
  return body as unknown as ImageCommitResult;
}

/** Manueller Datei-Upload (Nutzerwunsch: "der Admin soll selber bis zu
 * mehrere Bilder hinzufügen können") — ein Aufruf pro Datei, der Client
 * ruft bei mehreren ausgewählten Dateien mehrfach auf. imageBase64 OHNE
 * das "data:image/...;base64," Präfix. */
export async function commitManualImage(
  entityType: ImageEntityType,
  entityId: string,
  imageBase64: string,
  licenseStatus: "confirmed_free" | "confirmed_licensed",
): Promise<ImageCommitResult> {
  let res: Response;
  try {
    res = await fetch(functionsUrl("research-entity-image"), {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({ mode: "commit", entityType, entityId, imageBase64, licenseStatus }),
      signal: AbortSignal.timeout(60_000),
    });
  } catch (err) {
    return { committed: false, error: err instanceof Error ? err.message : String(err) };
  }

  let body: Record<string, unknown>;
  try {
    body = await res.json();
  } catch {
    return { committed: false, error: `Unerwartete Antwort (HTTP ${res.status}).` };
  }
  if (!res.ok) return { committed: false, error: (body.error as string) ?? `HTTP ${res.status}` };
  if (body.committed) revalidatePath("/media");
  return body as unknown as ImageCommitResult;
}
