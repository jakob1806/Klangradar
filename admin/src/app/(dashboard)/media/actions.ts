"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type LicenseStatus = "confirmed_free" | "confirmed_licensed" | "rejected";

// license_status-Übergänge sind bewusst redaktionelle Entscheidungen, nie
// automatisch (siehe 20260819000003_images_and_tags.sql). Alles in EINEM
// Datenbankaufruf (review_images, Migration 000101): vorher lief die
// Sammelfreigabe mit pro Bild 6–10 Aufrufen + Seiten-Neuaufbau ins
// Zeitlimit ("Freigeben klappt technisch nicht" bei ~1.000 Bildern).
async function reviewImages(imageIds: string[], status: LicenseStatus): Promise<number> {
  const supabase = await createClient();
  let done = 0;
  for (let i = 0; i < imageIds.length; i += 250) {
    const { data, error } = await supabase.rpc("review_images", { p_ids: imageIds.slice(i, i + 250), p_status: status });
    if (error) throw new Error(`${done} von ${imageIds.length} gespeichert, dann Fehler: ${error.message}`);
    done += (data as number | null) ?? 0;
  }
  revalidatePath("/media");
  return done;
}

async function setLicenseStatus(imageId: string, status: LicenseStatus) {
  await reviewImages([imageId], status);
}

export async function updateImageMetadata(formData: FormData) {
  const imageId = String(formData.get("imageId") ?? "");
  if (!imageId) throw new Error("Bild-ID fehlt.");
  const confidenceRaw = String(formData.get("confidenceScore") ?? "");
  const confidence = confidenceRaw === "" ? null : Number(confidenceRaw);
  if (confidence !== null && (!Number.isFinite(confidence) || confidence < 0 || confidence > 1)) {
    throw new Error("Confidence muss zwischen 0 und 1 liegen.");
  }
  const supabase = await createClient();
  const { error } = await supabase.from("images").update({
    photographer: String(formData.get("photographer") ?? "").trim() || null,
    credits: String(formData.get("credits") ?? "").trim() || null,
    license_name: String(formData.get("licenseName") ?? "").trim() || null,
    license_url: String(formData.get("licenseUrl") ?? "").trim() || null,
    confidence_score: confidence,
  }).eq("id", imageId);
  if (error) throw new Error(error.message);
  revalidatePath("/media");
}

export async function confirmImageFree(imageId: string) {
  await setLicenseStatus(imageId, "confirmed_free");
}

export async function confirmImageLicensed(imageId: string) {
  await setLicenseStatus(imageId, "confirmed_licensed");
}

export async function rejectImage(imageId: string) {
  await setLicenseStatus(imageId, "rejected");
}

/** Bulk-Variante für die Mehrfachauswahl im Bilder-Tab. */
export async function bulkSetLicenseStatus(imageIds: string[], status: LicenseStatus): Promise<number> {
  return reviewImages(imageIds, status);
}

/** Alle wartenden Bilder einer Quelle auf einmal (z. B. "Wikipedia");
 * sourceName null = alle wartenden Bilder. */
export async function bulkSetLicenseStatusBySource(sourceName: string | null, status: LicenseStatus): Promise<number> {
  const supabase = await createClient();
  const ids: string[] = [];
  for (let from = 0; ; from += 1000) {
    let query = supabase.from("images").select("id").eq("needs_review", true);
    if (sourceName) query = query.eq("source_name", sourceName);
    const { data, error } = await query.order("id").range(from, from + 999);
    if (error) throw new Error(error.message);
    ids.push(...(data ?? []).map((row) => row.id as string));
    if (!data || data.length < 1000) break;
  }
  return ids.length ? reviewImages(ids, status) : 0;
}

export async function approveAllFree(): Promise<void> {
  await bulkSetLicenseStatusBySource(null, "confirmed_free");
}

export async function approveAllLicensed(): Promise<void> {
  await bulkSetLicenseStatusBySource(null, "confirmed_licensed");
}

export async function approveSourceFree(sourceName: string): Promise<void> {
  await bulkSetLicenseStatusBySource(sourceName, "confirmed_free");
}

export async function approveSourceLicensed(sourceName: string): Promise<void> {
  await bulkSetLicenseStatusBySource(sourceName, "confirmed_licensed");
}

export async function rejectSource(sourceName: string): Promise<void> {
  await bulkSetLicenseStatusBySource(sourceName, "rejected");
}

export interface EnrichImagesResult {
  status: "ok" | "failed";
  perKind?: Record<string, {
    found: number;
    autoApplied: number;
    queuedForReview: number;
    errors: string[];
  }>;
  events?: {
    found: number;
    updated: number;
    errors: string[];
  };
  error?: string;
}

type EnrichmentKindResult = NonNullable<EnrichImagesResult["perKind"]>[string];
type EventEnrichmentResult = NonNullable<EnrichImagesResult["events"]>;

function isEnrichmentKindResult(value: unknown): value is EnrichmentKindResult {
  if (!value || typeof value !== "object") return false;
  const row = value as Record<string, unknown>;
  return typeof row.found === "number"
    && typeof row.autoApplied === "number"
    && typeof row.queuedForReview === "number"
    && Array.isArray(row.errors);
}

function isEventEnrichmentResult(value: unknown): value is EventEnrichmentResult {
  if (!value || typeof value !== "object") return false;
  const row = value as Record<string, unknown>;
  return typeof row.found === "number"
    && typeof row.updated === "number"
    && Array.isArray(row.errors);
}

// Reicht den echten Zugriffstoken der eingeloggten Person durch, NICHT den
// Anon-Key (der frühere Fehler hier: requireInternalAuth() erkennt im
// Anon-Key keine echte Nutzersession und lehnt mit 403 "Nicht berechtigt"
// ab, siehe backend/supabase/functions/_shared/internalAuth.ts). Gleiches
// Muster wie image-research/actions.ts's authHeaders() — funktioniert
// unabhängig davon, ob das für Cron/Server-zu-Server-Aufrufe gedachte
// INTERNAL_FUNCTION_SECRET in Vercel und Supabase synchron gesetzt ist.
async function authHeaders() {
  const supabase = await createClient();
  const [{ data: userData, error: userError }, { data: sessionData, error: sessionError }] = await Promise.all([
    supabase.auth.getUser(),
    supabase.auth.getSession(),
  ]);
  const accessToken = sessionData.session?.access_token;
  if (userError || sessionError || !userData.user || userData.user.is_anonymous || !accessToken) {
    throw new Error("Nicht angemeldet.");
  }
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  return {
    "Content-Type": "application/json",
    apikey: anonKey,
    Authorization: `Bearer ${accessToken}`,
  };
}

// Der manuelle Lauf auf der Medienseite arbeitet bewusst nur die großen
// Profilbild-Lücken ab (Personen, Ensembles) sowie Titelbilder für
// anstehende Events. Die übrigen Bildarten (Venues, Festivals) behalten
// ihre eigenen Recherchewege; so verbraucht ein Klick nicht wieder fast
// sein gesamtes Zeitbudget dafür, während Personen/Ensembles/Events liegen
// bleiben. Alle drei Edge-Aufrufe laufen innerhalb dieser einen Server
// Action parallel (Next dispatcht mehrere Client-Actions dagegen
// sequenziell).
export async function enrichEntityImages(): Promise<EnrichImagesResult> {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!baseUrl) {
    return { status: "failed", error: "Supabase-Konfiguration fehlt." };
  }
  const functionUrl = `${baseUrl}/functions/v1/enrich-entity-images`;

  let headers: Record<string, string>;
  try {
    headers = await authHeaders();
  } catch (err) {
    return { status: "failed", error: err instanceof Error ? err.message : String(err) };
  }

  async function runKind(type: "person" | "ensemble", table: "persons" | "ensembles") {
    const res = await fetch(functionUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({ type, limit: 8 }),
      signal: AbortSignal.timeout(90_000),
    });
    const body = await res.json() as Record<string, unknown>;
    if (!res.ok || body.error) {
      throw new Error((body.error as string) ?? `${type}: HTTP ${res.status}`);
    }
    const result = body[table];
    if (!isEnrichmentKindResult(result)) {
      throw new Error(`${type}: Unerwartete Antwort der Bildsuche.`);
    }
    return [table, result] as const;
  }

  async function runEvents(): Promise<EventEnrichmentResult> {
    // Kleineres Limit und deutlich längeres Timeout als person/ensemble:
    // der Event-Zweig macht zusätzlich zur eigentlichen Titelbildsuche noch
    // eine sequenzielle Websuche nach fehlenden Ticket-/Website-URLs
    // (discoverMissingEventUrls, bis zu 5 Events, je bis zu zwei externe
    // Such-API-Aufrufe nacheinander) UND lädt pro Event bis zu zwei echte
    // Fremdseiten (Website-/Ticket-URL) — beides zusammen sprengte live das
    // bisherige 90s-Timeout ("The operation was aborted due to timeout"),
    // das für person/ensemble dank raceImageSources() (parallele Quellen)
    // ausreicht, hier aber nicht.
    const res = await fetch(functionUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({ type: "event", limit: 4 }),
      signal: AbortSignal.timeout(150_000),
    });
    const body = await res.json() as Record<string, unknown>;
    if (!res.ok || body.error) {
      throw new Error((body.error as string) ?? `event: HTTP ${res.status}`);
    }
    if (!isEventEnrichmentResult(body.events)) {
      throw new Error("event: Unerwartete Antwort der Bildsuche.");
    }
    return body.events;
  }

  // allSettled statt allSettled+catch über alles: die Event-Suche macht
  // reale externe Seitenaufrufe und ist dadurch anfälliger für einen
  // Timeout als person/ensemble (raceImageSources, parallele Quellen,
  // siehe runKind) — ein Timeout dort soll nicht auch die längst fertigen
  // person/ensemble-Ergebnisse verwerfen ("Bildsuche fehlgeschlagen" für
  // alles, obwohl nur ein Teil betroffen war).
  const [personEnsembleResult, eventsResult] = await Promise.allSettled([
    Promise.all([
      runKind("person", "persons"),
      runKind("ensemble", "ensembles"),
    ]),
    runEvents(),
  ]);

  if (personEnsembleResult.status === "rejected") {
    return {
      status: "failed",
      error: `Bildsuche fehlgeschlagen: ${
        personEnsembleResult.reason instanceof Error ? personEnsembleResult.reason.message : String(personEnsembleResult.reason)
      }`,
    };
  }

  revalidatePath("/media");
  return {
    status: "ok",
    perKind: Object.fromEntries(personEnsembleResult.value),
    events: eventsResult.status === "fulfilled"
      ? eventsResult.value
      : {
        found: 0,
        updated: 0,
        errors: [
          `Event-Bildsuche fehlgeschlagen: ${
            eventsResult.reason instanceof Error ? eventsResult.reason.message : String(eventsResult.reason)
          }`,
        ],
      },
  };
}
