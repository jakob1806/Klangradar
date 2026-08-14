"use server";

import { createClient } from "@/lib/supabase/server";
import type { GalleryImage } from "@/lib/gallery-actions";

export interface WorkSearchResult {
  id: string;
  title: string;
  composerName: string | null;
}

export interface LinkedWorkImageResult extends WorkSearchResult {
  imageCount: number;
  previewUrl: string | null;
}

/** Werksuche für die manuelle Werk-Bild-Verknüpfung (/work-image-reuse) —
 * kein eigenes /works-Seiten-Verwaltungsmodul nötig, ein Suchfeld reicht
 * (Nutzerentscheidung). */
export async function searchWorks(query: string): Promise<WorkSearchResult[]> {
  const trimmed = query.trim();
  if (trimmed.length < 2) return [];

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("works")
    .select("id, title, composer:persons(full_name)")
    .ilike("title", `%${trimmed}%`)
    .order("title")
    .limit(15)
    .returns<{ id: string; title: string; composer: { full_name: string } | null }[]>();
  if (error) throw new Error(error.message);

  return (data ?? []).map((row) => ({
    id: row.id,
    title: row.title,
    composerName: row.composer?.full_name ?? null,
  }));
}

export async function getWorkGalleryImages(workId: string): Promise<GalleryImage[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("images")
    .select(
      "id, source_url, sort_order, crop_x, crop_y, crop_width, crop_height, review_status, quality_status, confidence_score, source_name, license_status, last_checked_at, warnings, venue_id",
    )
    .eq("origin_type", "work")
    .eq("origin_id", workId)
    .order("sort_order")
    .returns<GalleryImage[]>();
  if (error) throw new Error(error.message);
  return data ?? [];
}

/** Liefert alle Werke, für die bereits mindestens ein Werkbild existiert.
 * `images.origin_id` ist polymorph und hat deshalb keine direkte FK-Relation
 * zu `works`; die beiden kleinen Abfragen werden hier bewusst zusammengeführt.
 * Das erste Bild nach sort_order ist zugleich die Vorschau/Miniaturansicht. */
export async function listWorksWithGalleryImages(): Promise<LinkedWorkImageResult[]> {
  const supabase = await createClient();
  const { data: imageRows, error: imageError } = await supabase
    .from("images")
    .select("origin_id, source_url, storage_path, thumbnail_path, sort_order")
    .eq("origin_type", "work")
    .order("origin_id")
    .order("sort_order")
    .limit(2000)
    .returns<
      {
        origin_id: string;
        source_url: string;
        storage_path: string | null;
        thumbnail_path: string | null;
        sort_order: number;
      }[]
    >();
  if (imageError) throw new Error(imageError.message);

  const imagesByWork = new Map<string, typeof imageRows>();
  for (const image of imageRows ?? []) {
    const current = imagesByWork.get(image.origin_id) ?? [];
    current.push(image);
    imagesByWork.set(image.origin_id, current);
  }
  const workIds = [...imagesByWork.keys()];
  if (workIds.length === 0) return [];

  const { data: works, error: worksError } = await supabase
    .from("works")
    .select("id, title, composer:persons(full_name)")
    .in("id", workIds)
    .order("title")
    .returns<{ id: string; title: string; composer: { full_name: string } | null }[]>();
  if (worksError) throw new Error(worksError.message);

  return (works ?? []).map((work) => {
    const images = imagesByWork.get(work.id) ?? [];
    const preview = images[0];
    const storagePath = preview?.thumbnail_path ?? preview?.storage_path;
    const previewUrl = storagePath
      ? supabase.storage.from("ingested-images").getPublicUrl(storagePath).data.publicUrl
      : preview?.source_url ?? null;
    return {
      id: work.id,
      title: work.title,
      composerName: work.composer?.full_name ?? null,
      imageCount: images.length,
      previewUrl,
    };
  });
}

export interface VenueOption {
  id: string;
  name: string;
}

export async function listVenuesForSelect(): Promise<VenueOption[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("venues").select("id, name").order("name").returns<VenueOption[]>();
  if (error) throw new Error(error.message);
  return data ?? [];
}
