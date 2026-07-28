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

export type GalleryOriginType = "person" | "ensemble" | "event";

export interface GalleryCrop {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface GalleryImage {
  id: string;
  source_url: string;
  sort_order: number;
  crop_x: number | null;
  crop_y: number | null;
  crop_width: number | null;
  crop_height: number | null;
}

export async function addGalleryImage(
  originType: GalleryOriginType,
  originId: string,
  sourceUrl: string,
  path: string,
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
    storage_path: sourceUrl,
    sort_order: nextSortOrder,
    license_status: "confirmed_free",
    needs_review: false,
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
