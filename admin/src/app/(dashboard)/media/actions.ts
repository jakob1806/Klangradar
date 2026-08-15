"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

// Tabelle + Spalte, in die das Bild bei Freigabe geschrieben wird — venues/
// persons/ensembles/festivals haben je ein einzelnes photo_url-Feld,
// "organizer" bewusst ausgenommen (logo_url ist redaktionell etwas anderes
// als ein Veranstaltungsfoto). "event" braucht eine eigene Behandlung
// (image_urls ist ein Array), siehe applyToOrigin() unten.
const ORIGIN_TABLE: Record<string, string> = {
  venue: "venues",
  person: "persons",
  ensemble: "ensembles",
  festival: "festivals",
};

interface ImageRow {
  origin_type: string;
  origin_id: string;
  source_url: string;
  storage_path: string | null;
}

/** Schreibt das freigegebene Bild ins tatsächlich von der App ausgespielte
 * Feld der Ursprungs-Entität — ohne das bliebe eine Freigabe hier wirkungslos
 * (images war bisher rein Lizenz-Tracking, siehe Seitenkommentar auf
 * /media, "wird von der App aktuell noch nicht ausgespielt"). Best-effort:
 * ein Fehlschlag hier lässt die eigentliche Lizenz-Entscheidung nicht
 * scheitern, wird nur geloggt. */
async function applyToOrigin(
  supabase: Awaited<ReturnType<typeof createClient>>,
  image: ImageRow,
) {
  const publicUrl = image.storage_path
    ? supabase.storage.from("ingested-images").getPublicUrl(image.storage_path).data.publicUrl
    : image.source_url;
  if (image.origin_type === "event") {
    const { data: event, error: fetchError } = await supabase
      .from("events")
      .select("image_urls")
      .eq("id", image.origin_id)
      .maybeSingle();
    if (fetchError || !event) {
      console.error(`applyToOrigin event ${image.origin_id}: ${fetchError?.message ?? "nicht gefunden"}`);
      return;
    }
    const current: string[] = event.image_urls ?? [];
    if (current.includes(publicUrl)) return;
    const { error } = await supabase
      .from("events")
      .update({ image_urls: [...current, publicUrl] })
      .eq("id", image.origin_id);
    if (error) console.error(`applyToOrigin event ${image.origin_id}: ${error.message}`);
    return;
  }

  const table = ORIGIN_TABLE[image.origin_type];
  if (!table) return; // z.B. "organizer" — bewusst nicht automatisch übernommen

  const { error } = await supabase
    .from(table)
    .update({ photo_url: publicUrl })
    .eq("id", image.origin_id)
    .is("photo_url", null);
  if (error) console.error(`applyToOrigin ${table} ${image.origin_id}: ${error.message}`);
}

/** `is_primary` (welches Bild eine Entität repräsentiert) und `sort_order`
 * (welches Bild die Galerie an Position 0 zeigt) liefen bisher auseinander:
 * diese Funktion setzte nur is_primary, während sowohl die Admin- als auch
 * die App-Galerie ausschließlich nach sort_order sortieren (siehe
 * gallery-actions.ts's setPrimaryGalleryImage für dasselbe Muster bei
 * manueller Galerie-Pflege) — is_primary-Schreibvorgänge waren dadurch für
 * das, was tatsächlich angezeigt wird, wirkungslos. is_primary bleibt
 * kanonisch (explizit, indexiert, bereits korrekt gesetzt), sort_order wird
 * jetzt bei jeder Freigabe mit übernommen: das Bild rückt an Position 0,
 * alle anderen rutschen nach. */
async function setPrimaryAndSortOrder(
  supabase: Awaited<ReturnType<typeof createClient>>,
  originType: string,
  originId: string,
  imageId: string,
) {
  const { data: images, error } = await supabase
    .from("images")
    .select("id, sort_order")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .order("sort_order", { ascending: true });
  if (error) throw new Error(error.message);

  const rows = images ?? [];
  const target = rows.find((r) => r.id === imageId);
  const reordered = target ? [target, ...rows.filter((r) => r.id !== imageId)] : rows;

  for (let i = 0; i < reordered.length; i++) {
    if (reordered[i].sort_order === i) continue;
    const { error: updateError } = await supabase
      .from("images")
      .update({ sort_order: i })
      .eq("id", reordered[i].id);
    if (updateError) throw new Error(updateError.message);
  }

  await supabase.from("images").update({ is_primary: false })
    .eq("origin_type", originType).eq("origin_id", originId);
  await supabase.from("images").update({ is_primary: true }).eq("id", imageId);
}

export type LicenseStatus = "confirmed_free" | "confirmed_licensed" | "rejected";

// license_status-Übergänge sind bewusst redaktionelle Entscheidungen, nie
// automatisch (siehe 20260819000003_images_and_tags.sql) — needs_review
// wird hier explizit auf false gesetzt, sobald ein Redakteur eine
// Entscheidung getroffen hat (egal ob frei, lizenziert oder abgelehnt).
async function setLicenseStatus(imageId: string, status: LicenseStatus) {
  const supabase = await createClient();

  const { data: image, error: fetchError } = await supabase
    .from("images")
    .select("origin_type, origin_id, source_url, storage_path")
    .eq("id", imageId)
    .maybeSingle<ImageRow>();
  if (fetchError) throw new Error(fetchError.message);

  const { error } = await supabase
    .from("images")
    .update({
      license_status: status,
      needs_review: false,
      reviewed_at: new Date().toISOString(),
      reviewed_by: (await supabase.auth.getUser()).data.user?.id ?? null,
    })
    .eq("id", imageId);
  if (error) throw new Error(error.message);

  if ((status === "confirmed_free" || status === "confirmed_licensed") && image) {
    await applyToOrigin(supabase, image);
    await setPrimaryAndSortOrder(supabase, image.origin_type, image.origin_id, imageId);
  }

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "image",
    entityId: imageId,
    action: `license_${status}`,
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/media");
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

/** Bulk-Variante für die Mehrfachauswahl im Bilder-Tab — ruft dieselbe
 * setLicenseStatus()-Logik pro Bild auf (kein separater Bulk-SQL-Update),
 * damit applyToOrigin()/is_primary/system_logs für jedes Bild exakt wie
 * bei der Einzelaktion mitlaufen. */
export async function bulkSetLicenseStatus(imageIds: string[], status: LicenseStatus) {
  const results = await Promise.allSettled(imageIds.map((id) => setLicenseStatus(id, status)));
  const failed = results.filter((r) => r.status === "rejected");
  if (failed.length > 0) {
    throw new Error(`${failed.length} von ${imageIds.length} fehlgeschlagen.`);
  }
}

export interface EnrichImagesResult {
  status: "ok" | "failed";
  perKind?: Record<string, {
    found: number;
    autoApplied: number;
    queuedForReview: number;
    errors: string[];
  }>;
  error?: string;
}

type EnrichmentKindResult = NonNullable<EnrichImagesResult["perKind"]>[string];

function isEnrichmentKindResult(value: unknown): value is EnrichmentKindResult {
  if (!value || typeof value !== "object") return false;
  const row = value as Record<string, unknown>;
  return typeof row.found === "number"
    && typeof row.autoApplied === "number"
    && typeof row.queuedForReview === "number"
    && Array.isArray(row.errors);
}

// Der manuelle Lauf auf der Medienseite arbeitet bewusst nur die beiden
// großen Profilbild-Lücken ab. Die übrigen Bildarten behalten ihre eigenen
// Recherchewege; so verbraucht ein Klick nicht wieder fast sein gesamtes
// Zeitbudget für Venues/Festivals, während Personen und Ensembles liegen
// bleiben. Beide Edge-Aufrufe laufen innerhalb dieser einen Server Action
// parallel (Next dispatcht mehrere Client-Actions dagegen sequenziell).
export async function enrichEntityImages(): Promise<EnrichImagesResult> {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!baseUrl || !anonKey) {
    return { status: "failed", error: "Supabase-Konfiguration fehlt." };
  }
  // Eigene Konstanten halten die erfolgte Null-Prüfung auch innerhalb der
  // verschachtelten runKind()-Funktion für TypeScript eindeutig fest.
  const functionUrl = `${baseUrl}/functions/v1/enrich-entity-images`;
  const publicAnonKey = anonKey;

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { status: "failed", error: "Nicht angemeldet." };

  async function runKind(type: "person" | "ensemble", table: "persons" | "ensembles") {
    const res = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: publicAnonKey,
        Authorization: `Bearer ${publicAnonKey}`,
      },
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

  let entries: Array<readonly [string, EnrichmentKindResult]>;
  try {
    entries = await Promise.all([
      runKind("person", "persons"),
      runKind("ensemble", "ensembles"),
    ]);
  } catch (err) {
    return {
      status: "failed",
      error: `Bildsuche fehlgeschlagen: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  revalidatePath("/media");
  return {
    status: "ok",
    perKind: Object.fromEntries(entries),
  };
}
