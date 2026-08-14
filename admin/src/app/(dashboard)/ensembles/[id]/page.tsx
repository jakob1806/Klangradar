import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import { AiEnrichButton } from "@/components/ai-enrich-button";
import { EntityAuditButton } from "@/components/entity-audit-button";
import { EditorialAiAssistant } from "@/components/editorial-ai-assistant";
import type { GalleryImage } from "@/lib/gallery-actions";
import { updateEnsemble } from "../actions";
import { EnsembleDeleteControl } from "../ensemble-delete-control";
import { EnsembleForm, type EnsembleFormValues } from "../ensemble-form";

export default async function EditEnsemblePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data, error }, { data: venues }, { data: ensembles }, { data: images }] = await Promise.all([
    supabase
      .from("ensembles")
      .select(
        "slug, name, type, description_de, founded_year, member_count, home_venue_id, parent_ensemble_id, family_role, is_family_root, is_resolution_placeholder, website_url, photo_url, avatar_crop_x, avatar_crop_y, avatar_crop_width, avatar_crop_height, is_verified",
      )
      .eq("id", id)
      .maybeSingle<EnsembleFormValues>(),
    supabase.from("venues").select("id, name").order("name"),
    supabase.from("ensembles").select("id, name").eq("is_resolution_placeholder", false).order("name").returns<{ id: string; name: string }[]>(),
    // Nur freigegebene Bilder — siehe Kommentar in persons/[id]/page.tsx.
    supabase
      .from("images")
      .select("id, source_url, sort_order, crop_x, crop_y, crop_width, crop_height, review_status, quality_status, confidence_score, source_name, license_status, last_checked_at, warnings, use_as_event_fallback")
      .eq("origin_type", "ensemble")
      .eq("origin_id", id)
      .in("license_status", ["confirmed_free", "confirmed_licensed"])
      .order("sort_order", { ascending: true })
      .returns<GalleryImage[]>(),
  ]);

  if (error || !data) notFound();

  const parentEnsemble = (ensembles ?? []).find((e) => e.id === data.parent_ensemble_id);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">{data.name} bearbeiten</h1>
        <EnsembleDeleteControl ensembleId={id} ensembleName={data.name} />
      </div>
      <div className="mt-4 flex flex-wrap items-start gap-3">
        <AiEnrichButton entityType="ensemble" entityId={id} />
        <EntityAuditButton entityType="ensemble" entityId={id} />
      </div>
      <div className="mt-4"><EditorialAiAssistant entityType="ensemble" entityId={id} /></div>
      {parentEnsemble && (
        <div className="mt-4 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800">
          Gehört zum Ensemble{" "}
          <Link href={`/ensembles/${parentEnsemble.id}`} className="font-medium underline">
            {parentEnsemble.name}
          </Link>
        </div>
      )}
      {data.is_family_root && (
        <div className="mt-4 rounded-lg border border-violet-200 bg-violet-50 px-4 py-3 text-sm text-violet-800">
          Diese Seite ist eine Dachorganisation. Unterensembles und Auflösungsregeln findest du in der{" "}
          <Link href="/ensemble-families" className="font-medium underline">Familienverwaltung</Link>.
        </div>
      )}
      {data.is_resolution_placeholder && (
        <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          Technische Sammelbezeichnung: Sie wird bei Veranstaltungen automatisch auf ihre Ziel-Ensembles aufgeteilt.
        </div>
      )}
      <div className="mt-6">
        <EnsembleForm
          action={updateEnsemble.bind(null, id)}
          initial={data}
          venues={venues ?? []}
          ensembles={ensembles ?? []}
          ensembleId={id}
        />
      </div>
      <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
        <GalleryEditor
          originType="ensemble"
          originId={id}
          path={`/ensembles/${id}`}
          images={images ?? []}
          showEventFallbackToggle
        />
      </div>
    </div>
  );
}
