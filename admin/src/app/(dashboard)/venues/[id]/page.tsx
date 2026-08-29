import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import { AiEnrichButton } from "@/components/ai-enrich-button";
import { EntityAuditButton } from "@/components/entity-audit-button";
import type { GalleryImage } from "@/lib/gallery-actions";
import { updateVenue, getCityOptions } from "../actions";
import { VenueDeleteControl } from "../venue-delete-control";
import { VenueForm, type VenueFormValues } from "../venue-form";

export default async function EditVenuePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const [{ data, error }, { data: socialData }, { data: images }, cities, { data: affectedEventCount }] = await Promise.all([
    supabase.rpc("venue_with_latlng", { p_id: id }).maybeSingle<VenueFormValues>(),
    supabase.from("venues").select("social_links").eq("id", id).maybeSingle<Pick<VenueFormValues, "social_links">>(),
    // Nur freigegebene Bilder — siehe Kommentar in persons/[id]/page.tsx.
    supabase
      .from("images")
      .select("id, source_url, sort_order, crop_x, crop_y, crop_width, crop_height, review_status, quality_status, confidence_score, source_name, license_status, last_checked_at, warnings")
      .eq("origin_type", "venue")
      .eq("origin_id", id)
      .in("license_status", ["confirmed_free", "confirmed_licensed"])
      .order("sort_order", { ascending: true })
      .returns<GalleryImage[]>(),
    getCityOptions(),
    supabase.rpc("venue_event_count_for_city_change", { p_venue_id: id }),
  ]);

  if (error || !data) notFound();
  const initial = { ...data, social_links: socialData?.social_links ?? {} };

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{initial.name} bearbeiten</h1>
        <VenueDeleteControl venueId={id} venueName={initial.name} />
      </div>
      <div className="mt-4 flex flex-wrap items-start gap-3">
        <AiEnrichButton entityType="venue" entityId={id} />
        <EntityAuditButton entityType="venue" entityId={id} />
      </div>
      <div className="mt-6">
        <VenueForm
          action={updateVenue.bind(null, id)}
          initial={initial}
          cities={cities}
          affectedEventCount={affectedEventCount ?? 0}
        />
      </div>
      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <GalleryEditor originType="venue" originId={id} path={`/venues/${id}`} images={images ?? []} />
      </div>
    </div>
  );
}
