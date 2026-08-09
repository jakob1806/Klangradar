import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import { AiEnrichButton } from "@/components/ai-enrich-button";
import { EntityAuditButton } from "@/components/entity-audit-button";
import type { GalleryImage } from "@/lib/gallery-actions";
import { updateVenue } from "../actions";
import { VenueDeleteControl } from "../venue-delete-control";
import { VenueForm, type VenueFormValues } from "../venue-form";

export default async function EditVenuePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const [{ data, error }, { data: images }] = await Promise.all([
    supabase.rpc("venue_with_latlng", { p_id: id }).maybeSingle<VenueFormValues>(),
    // Nur freigegebene Bilder — siehe Kommentar in persons/[id]/page.tsx.
    supabase
      .from("images")
      .select("id, source_url, sort_order, crop_x, crop_y, crop_width, crop_height, review_status, quality_status, confidence_score, source_name, license_status, last_checked_at, warnings")
      .eq("origin_type", "venue")
      .eq("origin_id", id)
      .in("license_status", ["confirmed_free", "confirmed_licensed"])
      .order("sort_order", { ascending: true })
      .returns<GalleryImage[]>(),
  ]);

  if (error || !data) notFound();

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{data.name} bearbeiten</h1>
        <VenueDeleteControl venueId={id} venueName={data.name} />
      </div>
      <div className="mt-4 flex flex-wrap items-start gap-3">
        <AiEnrichButton entityType="venue" entityId={id} />
        <EntityAuditButton entityType="venue" entityId={id} />
      </div>
      <div className="mt-6">
        <VenueForm action={updateVenue.bind(null, id)} initial={data} />
      </div>
      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <GalleryEditor originType="venue" originId={id} path={`/venues/${id}`} images={images ?? []} />
      </div>
    </div>
  );
}
