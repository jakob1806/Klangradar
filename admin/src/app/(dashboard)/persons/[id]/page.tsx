import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import { AiEnrichButton } from "@/components/ai-enrich-button";
import type { GalleryImage } from "@/lib/gallery-actions";
import { updatePerson } from "../actions";
import { PersonDeleteControl } from "../person-delete-control";
import { PersonForm, type PersonFormValues } from "../person-form";

export default async function EditPersonPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("persons")
    .select(
      "slug, full_name, roles, instrument, nationality, birth_date, death_date, biography_de, website_url, photo_url, is_verified",
    )
    .eq("id", id)
    .maybeSingle<PersonFormValues>();

  if (error || !data) notFound();

  // Nur freigegebene Bilder — unreviewte KI-Kandidaten (license_status
  // 'unknown'/'rejected') laufen ausschließlich über die /media-Warteschlange,
  // sonst könnte hier versehentlich ein noch nicht geprüftes oder bereits
  // abgelehntes Bild einsortiert/zugeschnitten werden.
  const { data: images } = await supabase
    .from("images")
    .select("id, source_url, sort_order, crop_x, crop_y, crop_width, crop_height, review_status, quality_status, confidence_score, source_name, license_status, last_checked_at, warnings")
    .eq("origin_type", "person")
    .eq("origin_id", id)
    .in("license_status", ["confirmed_free", "confirmed_licensed"])
    .order("sort_order", { ascending: true })
    .returns<GalleryImage[]>();

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{data.full_name} bearbeiten</h1>
        <PersonDeleteControl personId={id} personName={data.full_name} />
      </div>
      <div className="mt-4">
        <AiEnrichButton entityType="person" entityId={id} />
      </div>
      <div className="mt-6">
        <PersonForm action={updatePerson.bind(null, id)} initial={data} />
      </div>
      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <GalleryEditor originType="person" originId={id} path={`/persons/${id}`} images={images ?? []} />
      </div>
    </div>
  );
}
