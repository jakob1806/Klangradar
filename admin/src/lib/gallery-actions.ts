"use server";

// Gemeinsame Server Actions für die Mehrfach-Bilder-Galerie (Personen +
// Ensembles, siehe 20260909000006_image_gallery_ordering_and_crop.sql) —
// eine Datei statt einer pro Entitätstyp, weil sich nur origin_type/
// origin_id und der zu revalidierende Pfad unterscheiden.
//
// Selbst hochgeladene Bilder gehen NICHT durch die /media-Freigabe-Queue:
// eine Redakteurin, die hier bewusst ein Foto auswählt, hat es bereits
// geprüft — anders als KI-gefundene Kandidaten aus enrich-entity-images,
// bei denen needs_review=true/license_status='unknown' der Startzustand
// bleibt.

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

export type GalleryOriginType = "person" | "ensemble" | "event" | "venue" | "work";

export interface GalleryCrop {
  x: number;
  y: number;
  width: number;
  height: number;
}

export type ReviewStatus = "pending" | "approved" | "rejected" | "needs_manual_review";
export type QualityStatus =
  | "valid"
  | "low_resolution"
  | "unreachable"
  | "invalid_format"
  | "duplicate"
  | "copyright_unclear";

export interface GalleryImage {
  id: string;
  source_url: string;
  sort_order: number;
  crop_x: number | null;
  crop_y: number | null;
  crop_width: number | null;
  crop_height: number | null;
  review_status: ReviewStatus;
  quality_status: QualityStatus;
  confidence_score: number | null;
  source_name: string | null;
  license_status: string | null;
  last_checked_at: string | null;
  warnings: string[] | null;
  /** Nur bei originType "work" befüllt/angezeigt — bindet das Bild an eine
   * bestimmte Venue (z.B. Zauberflöte NUR am Nationaltheater) statt werkweit
   * für jede Venue zu gelten (null). */
  venue_id?: string | null;
  /** Nur bei originType "person"/"ensemble" — als Standardbild für alle
   * Veranstaltungen dieser Entität ohne eigenes Bild markiert, siehe
   * setEventFallbackImage(). */
  use_as_event_fallback?: boolean;
}

export async function addGalleryImage(
  originType: GalleryOriginType,
  originId: string,
  sourceUrl: string,
  path: string,
  venueId?: string | null,
) {
  const supabase = await createClient();

  const { data: existing } = await supabase
    .from("images")
    .select("sort_order")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .order("sort_order", { ascending: false })
    .limit(1)
    .maybeSingle();

  const nextSortOrder = existing ? existing.sort_order + 1 : 0;

  const { error } = await supabase.from("images").insert({
    origin_type: originType,
    origin_id: originId,
    source_url: sourceUrl,
    venue_id: venueId ?? null,
    // NICHT storage_path: sourceUrl — storage_path wird von der App
    // (entity_gallery_providers.dart) als RELATIVER Pfad INNERHALB des
    // "ingested-images"-Buckets interpretiert (getPublicUrl(storagePath)).
    // sourceUrl ist hier aber schon eine volle öffentliche URL im Bucket
    // "entity-photos" (siehe oben, BUCKET-Konstante) — als storage_path
    // gespeichert entstand daraus eine doppelt verschachtelte, kaputte URL
    // (".../ingested-images/https://.../entity-photos/..."), die in der App
    // 404 zurückgab. Bug live bestätigt: Galerie-Bilder aus diesem Upload-
    // Weg verschwanden auf der Detailseite nach dem ersten Fehlversuch
    // wieder (CachedNetworkImage.errorWidget → Genre-Platzhalter). null
    // lässt GalleryImage.fromRow korrekt auf source_url zurückfallen.
    storage_path: null,
    sort_order: nextSortOrder,
    license_status: "confirmed_free",
    needs_review: false,
    // Konsistent mit needs_review: false oben (siehe Datei-Kommentar) — ein
    // manueller Admin-Upload ist bereits redaktionell geprüft, sonst würde
    // die neue review_status-Spalte hier ihren Default "pending" behalten
    // und in der Galerie fälschlich ein "Ausstehend"-Badge zeigen.
    review_status: "approved",
  });
  if (error) throw new Error(error.message);

  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "image",
    entityId: originId,
    action: "gallery_image_added",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath(path);
}

export async function deleteGalleryImage(imageId: string, path: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("images").delete().eq("id", imageId);
  if (error) throw new Error(error.message);
  revalidatePath(path);
}

/** Tauscht sort_order mit dem direkten Nachbarn — reicht für kleine
 * Galerien (wenige Bilder pro Künstler/Ensemble), kein Drag&Drop nötig. */
export async function moveGalleryImage(
  originType: GalleryOriginType,
  originId: string,
  imageId: string,
  direction: "up" | "down",
  path: string,
) {
  const supabase = await createClient();

  const { data: images, error } = await supabase
    .from("images")
    .select("id, sort_order")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .order("sort_order", { ascending: true });
  if (error) throw new Error(error.message);

  const rows = images ?? [];
  const index = rows.findIndex((r) => r.id === imageId);
  const swapIndex = direction === "up" ? index - 1 : index + 1;
  if (index === -1 || swapIndex < 0 || swapIndex >= rows.length) return;

  const a = rows[index];
  const b = rows[swapIndex];

  const { error: err1 } = await supabase
    .from("images")
    .update({ sort_order: b.sort_order })
    .eq("id", a.id);
  if (err1) throw new Error(err1.message);

  const { error: err2 } = await supabase
    .from("images")
    .update({ sort_order: a.sort_order })
    .eq("id", b.id);
  if (err2) throw new Error(err2.message);

  revalidatePath(path);
}

/** Setzt ein Bild direkt als Miniaturansicht/Titelbild, statt es per
 * moveGalleryImage Schritt für Schritt nach vorne zu schieben: alle
 * Bilder werden in ihrer aktuellen Reihenfolge neu durchnummeriert, mit
 * dem gewählten Bild an Position 0. */
export async function setPrimaryGalleryImage(
  originType: GalleryOriginType,
  originId: string,
  imageId: string,
  path: string,
) {
  const supabase = await createClient();

  const { data: images, error } = await supabase
    .from("images")
    .select("id, sort_order")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .order("sort_order", { ascending: true });
  if (error) throw new Error(error.message);

  const rows = images ?? [];
  const target = rows.find((r) => r.id === imageId);
  if (!target) return;

  const reordered = [target, ...rows.filter((r) => r.id !== imageId)];

  for (let i = 0; i < reordered.length; i++) {
    if (reordered[i].sort_order === i) continue;
    const { error: updateError } = await supabase
      .from("images")
      .update({ sort_order: i })
      .eq("id", reordered[i].id);
    if (updateError) throw new Error(updateError.message);
  }

  revalidatePath(path);
}

export async function saveGalleryImageCrop(
  imageId: string,
  crop: GalleryCrop | null,
  path: string,
) {
  const supabase = await createClient();

  const { error } = await supabase
    .from("images")
    .update(
      crop
        ? { crop_x: crop.x, crop_y: crop.y, crop_width: crop.width, crop_height: crop.height }
        : { crop_x: null, crop_y: null, crop_width: null, crop_height: null },
    )
    .eq("id", imageId);
  if (error) throw new Error(error.message);

  revalidatePath(path);
}

/** Runder Avatar-Fokuspunkt für den Profilfoto-Ausschnitt (Personen +
 * Ensembles, Nutzervorgabe) — eigene Spalten direkt auf persons/ensembles
 * (avatar_crop_x/y/width/height, siehe 20261007000005), unabhängig vom
 * 16:9-Galerie-Crop derselben images-Tabelle oben: der Avatar-Ausschnitt
 * gehört zum einzelnen photo_url-Feld, nicht zu einem bestimmten
 * Galeriebild. */
export async function saveAvatarCrop(
  entityType: "persons" | "ensembles",
  entityId: string,
  crop: GalleryCrop | null,
  path: string,
) {
  const supabase = await createClient();

  const { error } = await supabase
    .from(entityType)
    .update(
      crop
        ? {
            avatar_crop_x: crop.x,
            avatar_crop_y: crop.y,
            avatar_crop_width: crop.width,
            avatar_crop_height: crop.height,
          }
        : { avatar_crop_x: null, avatar_crop_y: null, avatar_crop_width: null, avatar_crop_height: null },
    )
    .eq("id", entityId);
  if (error) throw new Error(error.message);

  revalidatePath(path);
}

/** Bestätigen/Ablehnen/Als-zu-klein-markieren/Erneut-prüfen — die vier
 * Admin-Aktionen aus der Erweiterungsvorgabe für die zentrale Bild-
 * datenbank (Abschnitt 7: "Bild bestätigen, Bild ablehnen, ... Bild als zu
 * klein markieren, ... Bild erneut prüfen"). review_status/quality_status
 * sind bewusst unabhängig voneinander (siehe
 * 20261006000005_image_review_quality_status.sql) — Ablehnen ändert nur
 * review_status, nicht license_status oder quality_status, ein technisch
 * einwandfreies Bild kann trotzdem redaktionell abgelehnt werden (falsches
 * Motiv, falsche Person) und umgekehrt. */
export async function confirmGalleryImage(imageId: string, path: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("images").update({ review_status: "approved" }).eq("id", imageId);
  if (error) throw new Error(error.message);
  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "image",
    entityId: imageId,
    action: "image_review_confirmed",
    actor: user?.email ?? user?.id ?? "unknown",
  });
  revalidatePath(path);
}

export async function rejectGalleryImage(imageId: string, path: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("images").update({ review_status: "rejected" }).eq("id", imageId);
  if (error) throw new Error(error.message);
  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "image",
    entityId: imageId,
    action: "image_review_rejected",
    actor: user?.email ?? user?.id ?? "unknown",
  });
  // Kein revalidatePath-only-Update: abgelehnte Bilder bleiben in der
  // Galerie sichtbar (mit rotem Badge), werden nur nicht mehr automatisch
  // vorgeschlagen (siehe research-entity-image/index.ts, isRejectedImageUrl,
  // und imagePipeline.ts ensureCoverImage-Dedupe) — bewusst kein Löschen,
  // die Redaktion soll nachvollziehen können, was schon abgelehnt wurde.
  revalidatePath(path);
}

export async function markGalleryImageTooSmall(imageId: string, path: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("images")
    .update({ quality_status: "low_resolution", last_checked_at: new Date().toISOString() })
    .eq("id", imageId);
  if (error) throw new Error(error.message);
  const { data: { user } } = await supabase.auth.getUser();
  await logSystemAction(supabase, {
    entityType: "image",
    entityId: imageId,
    action: "image_marked_low_resolution",
    actor: user?.email ?? user?.id ?? "unknown",
  });
  revalidatePath(path);
}

/** Prüft die Bildquelle erneut auf Erreichbarkeit und gleicht quality_status
 * gegen die schon gespeicherten width/height ab. Lädt das Bild NICHT
 * erneut komplett herunter/dekodiert es nicht neu (im Admin — anders als
 * in der Edge-Function-Pipeline — keine Bildverarbeitungs-Bibliothek
 * verfügbar) — für eine reine Erreichbarkeits-/Mindestauflösungs-Prüfung
 * reicht das: die tatsächlichen Pixel-Maße wurden schon beim ersten Import
 * per ImageMagick ermittelt und ändern sich für dieselbe Datei nicht. */
export async function recheckGalleryImage(imageId: string, path: string): Promise<QualityStatus> {
  const supabase = await createClient();
  const { data: image, error: fetchError } = await supabase
    .from("images")
    .select("source_url, width, height")
    .eq("id", imageId)
    .maybeSingle();
  if (fetchError) throw new Error(fetchError.message);
  if (!image) throw new Error("Bild nicht gefunden.");

  let quality: QualityStatus = "valid";
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8_000);
    let res: Response;
    try {
      res = await fetch(image.source_url, { method: "HEAD", signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
    if (!res.ok) quality = "unreachable";
  } catch {
    quality = "unreachable";
  }
  if (quality === "valid" && image.width != null && image.height != null) {
    if (image.width < 640 || image.height < 480) quality = "low_resolution";
  }

  const { error } = await supabase
    .from("images")
    .update({ quality_status: quality, last_checked_at: new Date().toISOString() })
    .eq("id", imageId);
  if (error) throw new Error(error.message);

  revalidatePath(path);
  return quality;
}

/** Bindet ein bereits verknüpftes Werk-Bild nachträglich an eine bestimmte
 * Venue (oder löst die Bindung mit venueId=null wieder, dann gilt es wieder
 * werkweit) — Nutzervorgabe "Zauberflöte an der Bayerischen Staatsoper" vs.
 * "das Bild für das Werk, egal an welcher Venue". */
export async function setGalleryImageVenue(imageId: string, venueId: string | null, path: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("images").update({ venue_id: venueId }).eq("id", imageId);
  if (error) throw new Error(error.message);
  revalidatePath(path);
}

/** Markiert ein Galeriebild als Standardbild für alle Veranstaltungen dieser
 * Person/dieses Ensembles ohne eigenes Bild (write.ts ensureEntityCoverImage
 * bevorzugt es dann vor dem allgemeinen photo_url-Profilfoto). Höchstens
 * eines pro Entität — der Partial-Unique-Index (siehe Migration
 * 20261013000011) erzwingt das auch auf DB-Ebene, hier zusätzlich explizit
 * erst die alte Markierung lösen, damit kein Unique-Constraint-Fehler bei
 * zwei parallelen Updates entsteht. flag=false entfernt die Markierung
 * wieder (dann greift wieder photo_url). */
export async function setEventFallbackImage(
  originType: GalleryOriginType,
  originId: string,
  imageId: string,
  flag: boolean,
  path: string,
) {
  const supabase = await createClient();
  const { error: clearError } = await supabase
    .from("images")
    .update({ use_as_event_fallback: false })
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .eq("use_as_event_fallback", true);
  if (clearError) throw new Error(clearError.message);

  if (flag) {
    const { error } = await supabase.from("images").update({ use_as_event_fallback: true }).eq("id", imageId);
    if (error) throw new Error(error.message);
  }

  revalidatePath(path);
}
