import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Field, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { ImageUploadField } from "@/components/image-upload-field";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import type { GalleryImage } from "@/lib/gallery-actions";
import { AvatarCropButton } from "@/components/entity-gallery/avatar-crop-button";
import {
  EDITABLE_FIELDS_FOR_ENTITY_TYPE,
  NAME_COLUMN_FOR_ENTITY_TYPE,
  TABLE_FOR_ENTITY_TYPE,
  type ClaimableEntityType,
} from "@/lib/entity-tables";
import { submitEditSuggestion } from "./actions";

export const dynamic = "force-dynamic";

const VALID_ENTITY_TYPES: ClaimableEntityType[] = ["organizer", "venue", "person", "ensemble"];

function isTextArea(field: string) {
  return field.endsWith("_de") || field.endsWith("_en");
}

function inputType(field: string) {
  if (field.endsWith("_url")) return "url";
  if (field === "contact_email") return "email";
  return "text";
}

const SOCIAL_PLATFORMS = ["instagram", "facebook", "youtube", "spotify", "tiktok", "linkedin"] as const;

export default async function EditEntityProfilePage({
  params,
}: {
  params: Promise<{ entityType: string; entityId: string }>;
}) {
  const { entityType: rawType, entityId } = await params;
  if (!VALID_ENTITY_TYPES.includes(rawType as ClaimableEntityType)) notFound();
  const entityType = rawType as ClaimableEntityType;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: claim } = await supabase
    .from("entity_claims")
    .select("id")
    .eq("entity_type", entityType)
    .eq("entity_id", entityId)
    .eq("user_id", user!.id)
    .eq("status", "approved")
    .maybeSingle();

  if (!claim) {
    return (
      <div className="mx-auto max-w-xl px-6 py-16 text-center text-[#48484a]">
        Du hast keinen genehmigten Zugriff auf dieses Profil.
      </div>
    );
  }

  const fields: Record<string, string> = EDITABLE_FIELDS_FOR_ENTITY_TYPE[entityType];
  const fieldNames = Object.keys(fields);
  const nameColumn = NAME_COLUMN_FOR_ENTITY_TYPE[entityType];

  const { data: entity } = await supabase
    .from(TABLE_FOR_ENTITY_TYPE[entityType])
    .select("*")
    .eq("id", entityId)
    .maybeSingle();

  if (!entity) notFound();
  const entityRecord = entity as unknown as Record<string, unknown>;
  const socialLinks = (entityRecord.social_links ?? {}) as Record<string, string>;
  const galleryOrigin = entityType === "person" || entityType === "ensemble" || entityType === "venue" ? entityType : null;
  const { data: galleryImages } = galleryOrigin ? await supabase
    .from("images")
    .select("id, source_url, sort_order, crop_x, crop_y, crop_width, crop_height, review_status, quality_status, confidence_score, source_name, license_status, last_checked_at, warnings")
    .eq("origin_type", galleryOrigin).eq("origin_id", entityId).order("sort_order")
    .returns<GalleryImage[]>() : { data: [] as GalleryImage[] };

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <h1 className="type-heading mb-2 text-2xl text-[#1d1d1f]">Profil bearbeiten</h1>
      <p className="mb-6 text-sm text-[#86868b]">{(entityRecord[nameColumn] as string) ?? ""}</p>

        <form action={submitEditSuggestion.bind(null, entityType, entityId)} className="flex flex-col gap-4">
          {fieldNames.map((field) => field === "social_links" ? (
            <div key={field} className="rounded-xl border border-black/[0.06] bg-white p-4"><p className="text-sm font-semibold text-[#1d1d1f]">Social Media</p><p className="mt-1 text-xs text-[#86868b]">Bitte vollständige Profil-Links mit https:// eintragen. In den Apps erscheinen später Icon und Plattformname, nie die rohe URL.</p><div className="mt-4 grid gap-3 sm:grid-cols-2">{SOCIAL_PLATFORMS.map((platform) => <Field key={platform} label={platform[0].toUpperCase() + platform.slice(1)}><TextInput name={`social_${platform}`} type="url" defaultValue={socialLinks[platform] ?? ""} placeholder={`https://www.${platform}.com/deinprofil`} /></Field>)}</div></div>
          ) : field === "gallery_urls" ? (
            <div key={field}>{galleryOrigin ? <GalleryEditor originType={galleryOrigin} originId={entityId} path={`/veranstalter/profile/${entityType}/${entityId}`} images={galleryImages ?? []} storagePrefix={`claimed-gallery/${entityType}/${user!.id}`} /> : <Field label="Galeriebilder"><TextArea name={field} rows={5} defaultValue="" /></Field>}</div>
          ) : field === "photo_url" ? (
            <div key={field}><ImageUploadField name={field} initialUrl={(entityRecord[field] as string) ?? null} entityType={`claimed/${entityType}/${user!.id}`} shape={entityType === "person" ? "circle" : "rounded"} label={entityType === "person" ? "Profilbild (rund)" : "Hauptbild"} /></div>
          ) : (
            <Field key={field} label={fields[field]}>
              {isTextArea(field) ? (
                <TextArea name={field} rows={4} defaultValue={(entityRecord[field] as string) ?? ""} />
              ) : (
                <TextInput name={field} type={inputType(field)} defaultValue={(entityRecord[field] as string) ?? ""} />
              )}
            </Field>
          ))}
          <p className="text-xs text-neutral-400">Dein Claim ist bestätigt. Änderungen werden sofort veröffentlicht.</p>
          <div>
            <SubmitButton>Änderungen veröffentlichen</SubmitButton>
          </div>
        </form>
      {galleryOrigin && typeof entityRecord.photo_url === "string" && entityRecord.photo_url && (
        <div className="mt-8 border-t border-black/[0.06] pt-6">
          <p className="mb-3 text-sm font-semibold text-[#1d1d1f]">Runder Ausschnitt für App-Miniaturen</p>
          <p className="mb-4 text-sm text-[#86868b]">Lege fest, welcher Bereich deines Hauptbilds in runden Profilbildern erscheint.</p>
          <AvatarCropButton entityType={`${galleryOrigin}s` as "persons" | "ensembles" | "venues"} entityId={entityId} photoUrl={entityRecord.photo_url as string} initialCrop={entityRecord.avatar_crop_x != null && entityRecord.avatar_crop_y != null && entityRecord.avatar_crop_width != null && entityRecord.avatar_crop_height != null ? { x: Number(entityRecord.avatar_crop_x), y: Number(entityRecord.avatar_crop_y), width: Number(entityRecord.avatar_crop_width), height: Number(entityRecord.avatar_crop_height) } : null} path={`/veranstalter/profile/${entityType}/${entityId}`} />
        </div>
      )}
    </div>
  );
}
