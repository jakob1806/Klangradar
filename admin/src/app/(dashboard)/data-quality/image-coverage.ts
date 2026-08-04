// Abschnitt 3/F der Gesamtüberarbeitung: "Bericht über Abdeckung/fehlende
// Bilder/problematische URLs/Dubletten/Lizenzstatus" — bisher gab es nur
// rohe Gap-Listen (/media/gaps), keine Kennzahlen. Bewusst über den GESAMTEN
// Bestand (nicht nur die 90-Tage-Auswahl aus completeness.ts) — eine
// Abdeckungs-Kennzahl soll den ganzen Katalog zeigen, nicht nur bevorstehende
// Termine.
import { createClient } from "@/lib/supabase/server";

export interface ImageCoverageReport {
  venues: { total: number; withImage: number };
  persons: { total: number; withImage: number };
  ensembles: { total: number; withImage: number };
  events: { total: number; withImage: number };
  licenseStatusCounts: Record<string, number>;
  needsReviewCount: number;
  /** Bilder mit identischem content_hash, aber unterschiedlichem Origin —
   * echte Dubletten (dieselbe Datei mehrfach importiert), nicht die
   * bewusste Wiederverwendung innerhalb desselben Origins. */
  duplicateContentHashGroups: number;
  totalImages: number;
}

export interface ImageRow {
  origin_type: string;
  origin_id: string;
  license_status: string;
  needs_review: boolean;
  content_hash: string | null;
}

/** Reine Aggregation, getrennt vom Supabase-Fetch — testbar ohne DB-Mock,
 * siehe image-coverage.test.ts. */
export function aggregateImageCoverage(
  images: ImageRow[],
  counts: { venues: number; persons: number; ensembles: number; events: number },
  eventsWithImageCount: number,
): ImageCoverageReport {
  const imagedOrigins = { venue: new Set<string>(), person: new Set<string>(), ensemble: new Set<string>() };
  const licenseStatusCounts: Record<string, number> = {};
  let needsReviewCount = 0;
  const contentHashOrigins = new Map<string, Set<string>>();

  for (const row of images) {
    if (row.license_status !== "rejected" && row.origin_type in imagedOrigins) {
      imagedOrigins[row.origin_type as keyof typeof imagedOrigins].add(row.origin_id);
    }
    licenseStatusCounts[row.license_status] = (licenseStatusCounts[row.license_status] ?? 0) + 1;
    if (row.needs_review) needsReviewCount++;
    if (row.content_hash) {
      const key = `${row.origin_type}:${row.origin_id}`;
      const set = contentHashOrigins.get(row.content_hash) ?? new Set<string>();
      set.add(key);
      contentHashOrigins.set(row.content_hash, set);
    }
  }

  let duplicateContentHashGroups = 0;
  for (const origins of contentHashOrigins.values()) {
    if (origins.size > 1) duplicateContentHashGroups++;
  }

  return {
    venues: { total: counts.venues, withImage: imagedOrigins.venue.size },
    persons: { total: counts.persons, withImage: imagedOrigins.person.size },
    ensembles: { total: counts.ensembles, withImage: imagedOrigins.ensemble.size },
    events: { total: counts.events, withImage: eventsWithImageCount },
    licenseStatusCounts,
    needsReviewCount,
    duplicateContentHashGroups,
    totalImages: images.length,
  };
}

export async function fetchImageCoverageReport(): Promise<{ report: ImageCoverageReport | null; error: string | null }> {
  const supabase = await createClient();

  const [venueCount, personCount, ensembleCount, eventCount, images, events] = await Promise.all([
    supabase.from("venues").select("id", { count: "exact", head: true }),
    supabase.from("persons").select("id", { count: "exact", head: true }),
    supabase.from("ensembles").select("id", { count: "exact", head: true }),
    supabase.from("events").select("id", { count: "exact", head: true }),
    supabase.from("images").select("origin_type, origin_id, license_status, needs_review, content_hash"),
    supabase.from("events").select("id, image_urls"),
  ]);

  if (venueCount.error || personCount.error || ensembleCount.error || eventCount.error || images.error || events.error) {
    const firstError =
      venueCount.error ?? personCount.error ?? ensembleCount.error ?? eventCount.error ?? images.error ?? events.error;
    return { report: null, error: firstError?.message ?? "Unbekannter Fehler" };
  }

  const eventsWithImage = (events.data ?? []).filter((e) => e.image_urls && e.image_urls.length > 0).length;

  return {
    report: aggregateImageCoverage(
      images.data ?? [],
      {
        venues: venueCount.count ?? 0,
        persons: personCount.count ?? 0,
        ensembles: ensembleCount.count ?? 0,
        events: eventCount.count ?? 0,
      },
      eventsWithImage,
    ),
    error: null,
  };
}
