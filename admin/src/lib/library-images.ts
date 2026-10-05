import type { SupabaseClient } from "@supabase/supabase-js";

// Gemeinsame Bildauflösung für die Bibliothek im Veranstalterportal. Spiegelt
// die Kette der Apps (EventRepository.enrichingImages): eigenes Event-Bild ->
// Galerie des Events -> Venue -> Mitwirkende. Ohne diese Kette zeigten die
// meisten Events "kein Bild", obwohl sie in der App ein Bild haben.

type GalleryRow = {
  origin_id: string;
  thumbnail_path: string | null;
  storage_path: string | null;
  source_url: string | null;
  sort_order: number | null;
};

export const LIBRARY_PAGE_SIZE = 48;

const CHUNK = 75;

export async function loadGalleryImages(supabase: SupabaseClient, originIds: string[]): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  const unique = [...new Set(originIds)];
  for (let start = 0; start < unique.length; start += CHUNK) {
    const { data } = await supabase
      .from("images")
      .select("origin_id, thumbnail_path, storage_path, source_url, sort_order")
      .in("origin_id", unique.slice(start, start + CHUNK))
      .in("license_status", ["confirmed_free", "confirmed_licensed"])
      .eq("quality_status", "valid")
      .order("sort_order", { ascending: true })
      .returns<GalleryRow[]>();
    for (const row of data ?? []) {
      if (result.has(row.origin_id)) continue;
      const path = row.thumbnail_path ?? row.storage_path;
      const url = path ? supabase.storage.from("ingested-images").getPublicUrl(path).data.publicUrl : row.source_url;
      if (url) result.set(row.origin_id, url);
    }
  }
  return result;
}

export type EventImageInput = {
  id: string;
  image_urls: string[] | null;
  venues: { id: string; photo_url: string | null } | null;
  event_participants: { persons: { id: string; photo_url: string | null } | null; ensembles: { id: string; photo_url: string | null } | null }[] | null;
};

export async function resolveEventImages(supabase: SupabaseClient, events: EventImageInput[]): Promise<Map<string, string>> {
  const ids = events.flatMap((e) => [
    e.id,
    e.venues?.id,
    ...(e.event_participants ?? []).flatMap((p) => [p.persons?.id, p.ensembles?.id]),
  ]).filter((id): id is string => Boolean(id));
  const gallery = await loadGalleryImages(supabase, ids);

  const resolved = new Map<string, string>();
  for (const e of events) {
    const url =
      e.image_urls?.[0] ??
      gallery.get(e.id) ??
      (e.venues ? (gallery.get(e.venues.id) ?? e.venues.photo_url) : null) ??
      (e.event_participants ?? []).map((p) => (p.persons ? (gallery.get(p.persons.id) ?? p.persons.photo_url) : null) ?? (p.ensembles ? (gallery.get(p.ensembles.id) ?? p.ensembles.photo_url) : null)).find(Boolean) ??
      null;
    if (url) resolved.set(e.id, url);
  }
  return resolved;
}

export function pageRange(page: number) {
  const from = (page - 1) * LIBRARY_PAGE_SIZE;
  return { from, to: from + LIBRARY_PAGE_SIZE - 1 };
}
