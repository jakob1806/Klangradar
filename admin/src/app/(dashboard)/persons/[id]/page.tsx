import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import { AiEnrichButton } from "@/components/ai-enrich-button";
import { EntityAuditButton } from "@/components/entity-audit-button";
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
  const [{ data, error }, { data: ensembles }] = await Promise.all([
    supabase
      .from("persons")
      .select(
        "slug, full_name, first_name, middle_name, last_name, roles, instrument, nationality, birth_date, death_date, is_deceased, biography_de, website_url, photo_url, avatar_crop_x, avatar_crop_y, avatar_crop_width, avatar_crop_height, member_of_ensemble_id, is_verified",
      )
      .eq("id", id)
      .maybeSingle<PersonFormValues & { full_name: string }>(),
    supabase.from("ensembles").select("id, name").order("name").returns<{ id: string; name: string }[]>(),
  ]);

  if (error || !data) notFound();

  const parentEnsemble = (ensembles ?? []).find((e) => e.id === data.member_of_ensemble_id);

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
      <div className="mt-4 flex flex-wrap items-start gap-3">
        <AiEnrichButton entityType="person" entityId={id} />
        <EntityAuditButton entityType="person" entityId={id} />
      </div>
      {parentEnsemble && (
        <div className="mt-4 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800">
          Gehört zum Ensemble{" "}
          <Link href={`/ensembles/${parentEnsemble.id}`} className="font-medium underline">
            {parentEnsemble.name}
          </Link>
        </div>
      )}
      <div className="mt-6">
        <PersonForm action={updatePerson.bind(null, id)} initial={data} ensembles={ensembles ?? []} personId={id} />
      </div>
      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <GalleryEditor originType="person" originId={id} path={`/persons/${id}`} images={images ?? []} />
      </div>
    </div>
  );
}
