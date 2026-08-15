"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type ImageEntityType = "person" | "venue" | "ensemble" | "event" | "work" | "editorial_collection";

export interface ImageSearchResult {
  found: boolean;
  imageUrl?: string;
  /** Server-seitig heruntergeladene Vorschau-Kopie (ohne "data:...;base64,"
   * Präfix) — siehe research-entity-image/index.ts downloadForPreview().
   * Bevorzugt fürs <img>-Preview nutzen statt imageUrl direkt zu hotlinken:
   * einige Quellseiten blocken das per Referer-Check, die Vorschau blieb
   * dann leer, obwohl die Recherche selbst erfolgreich war. */
  imagePreviewBase64?: string;
  imagePreviewMimeType?: string;
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

async function authHeaders() {
  const supabase = await createClient();
  const [{ data: userData, error: userError }, { data: sessionData, error: sessionError }] = await Promise.all([
    supabase.auth.getUser(),
    supabase.auth.getSession(),
  ]);
  const accessToken = sessionData.session?.access_token;
  if (userError || sessionError || !userData.user || userData.user.is_anonymous || !accessToken) {
    throw new Error("Die Admin-Sitzung ist abgelaufen. Bitte erneut anmelden.");
  }
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  return {
    "Content-Type": "application/json",
    apikey: anonKey,
    Authorization: `Bearer ${accessToken}`,
  };
}

function requestError(err: unknown, operation: string) {
  const timedOut = err instanceof Error && (err.name === "TimeoutError" || err.name === "AbortError");
  if (timedOut) {
    return `${operation} dauert länger als erwartet. Bitte erneut versuchen oder einen konkreten Bild-/Seitenlink angeben.`;
  }
  return err instanceof Error ? err.message : String(err);
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
      headers: await authHeaders(),
      body: JSON.stringify({ mode: "search", entityType, entityId, sourceUrl }),
      // Offizielle Websites werden über mehrere Unterseiten (Presse,
      // Biografie, Galerie) durchsucht. 30 Sekunden waren dafür zu knapp
      // und ließen die UI so aussehen, als funktioniere die Suche nicht.
      signal: AbortSignal.timeout(90_000),
    });
  } catch (err) {
    return { found: false, error: requestError(err, "Die Bildsuche") };
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
      headers: await authHeaders(),
      body: JSON.stringify({ mode: "commit", entityType, entityId, ...input }),
      signal: AbortSignal.timeout(120_000),
    });
  } catch (err) {
    return { committed: false, error: requestError(err, "Das Speichern") };
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
      headers: await authHeaders(),
      body: JSON.stringify({ mode: "commit", entityType, entityId, imageBase64, licenseStatus }),
      signal: AbortSignal.timeout(120_000),
    });
  } catch (err) {
    return { committed: false, error: requestError(err, "Der Upload") };
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
