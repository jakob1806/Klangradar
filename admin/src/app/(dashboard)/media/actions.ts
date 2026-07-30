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
    await supabase.from("images").update({ is_primary: false })
      .eq("origin_type", image.origin_type).eq("origin_id", image.origin_id);
    await supabase.from("images").update({ is_primary: true }).eq("id", imageId);
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
  perKind?: Record<string, { found: number; queued: number; errors: string[] }>;
  events?: { found: number; updated: number; errors: string[] };
  error?: string;
}

// Ruft die enrich-entity-images Edge Function auf: sucht Wikimedia-Commons-
// Bilder für Venues/Personen/Ensembles/Festivals ohne eigenes Foto (landen
// hier zur Prüfung, needs_review=true) und übernimmt Venue-Fotos als
// Titelbild für bevorstehende Events ohne eigenes Bild.
export async function enrichEntityImages(): Promise<EnrichImagesResult> {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  let res: Response;
  try {
    res = await fetch(`${baseUrl}/functions/v1/enrich-entity-images`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey ?? "",
        Authorization: `Bearer ${anonKey ?? ""}`,
      },
      // Ohne limit läuft die Function mit ihrem Default (8) über alle 4
      // Entity-Kinds (venues/persons/ensembles/festivals) UND die Event-
      // Cover-Suche nacheinander durch — jeder Eintrag mit eigenen externen
      // Websuchen. Das dauert live regelmäßig länger als 60s (Nutzerfeedback:
      // "The operation was aborted due to timeout"). limit:3 hält den
      // manuellen Button-Klick verlässlich innerhalb des Zeitlimits; der
      // automatische Cron läuft ohnehin weiter im Hintergrund mit eigenem
      // Takt für den Rest.
      body: JSON.stringify({ limit: 3 }),
      signal: AbortSignal.timeout(90_000),
    });
  } catch (err) {
    return {
      status: "failed",
      error: `enrich-entity-images nicht erreichbar: ${err instanceof Error ? err.message : String(err)}`,
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

  revalidatePath("/media");

  const { events, ...perKind } = body;
  return {
    status: "ok",
    perKind: perKind as Record<string, { found: number; queued: number; errors: string[] }>,
    events: events as { found: number; updated: number; errors: string[] },
  };
}
