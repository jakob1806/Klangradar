import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/organizer/submit-button";
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
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/organizer/ui/card";
import { Input, Textarea } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { Separator } from "@/components/organizer/ui/separator";

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
      <div className="mx-auto max-w-xl px-6 py-16 text-center text-[#726c78]">
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
    <div>
      <PageHeader eyebrow="Profil" title="Profil bearbeiten" description={(entityRecord[nameColumn] as string) ?? ""} />
      <PageBody className="mx-auto flex max-w-2xl flex-col gap-8">
        <Card>
          <CardContent className="pt-5">
            <form action={submitEditSuggestion.bind(null, entityType, entityId)} className="flex flex-col gap-5">
              {fieldNames.map((field) => field === "social_links" ? (
                <Card key={field}>
                  <CardHeader>
                    <CardTitle>Social Media</CardTitle>
                    <CardDescription>
                      Bitte vollständige Profil-Links mit https:// eintragen. In den Apps erscheinen später Icon und Plattformname,
                      nie die rohe URL.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="grid gap-3 sm:grid-cols-2">
                    {SOCIAL_PLATFORMS.map((platform) => (
                      <div key={platform} className="flex flex-col gap-1.5">
                        <Label>{platform[0].toUpperCase() + platform.slice(1)}</Label>
                        <Input
                          name={`social_${platform}`}
                          type="url"
                          defaultValue={socialLinks[platform] ?? ""}
                          placeholder={`https://www.${platform}.com/deinprofil`}
                        />
                      </div>
                    ))}
                  </CardContent>
                </Card>
              ) : field === "gallery_urls" ? (
                <div key={field}>
                  {galleryOrigin ? (
                    <GalleryEditor
                      originType={galleryOrigin}
                      originId={entityId}
                      path={`/veranstalter/profile/${entityType}/${entityId}`}
                      images={galleryImages ?? []}
                      storagePrefix={`claimed-gallery/${entityType}/${user!.id}`}
                    />
                  ) : (
                    <div className="flex flex-col gap-1.5">
                      <Label>Galeriebilder</Label>
                      <Textarea name={field} rows={5} defaultValue="" />
                    </div>
                  )}
                </div>
              ) : field === "photo_url" ? (
                <div key={field}>
                  <ImageUploadField
                    name={field}
                    initialUrl={(entityRecord[field] as string) ?? null}
                    entityType={`claimed/${entityType}/${user!.id}`}
                    shape={entityType === "person" ? "circle" : "rounded"}
                    label={entityType === "person" ? "Profilbild (rund)" : "Hauptbild"}
                  />
                </div>
              ) : (
                <div key={field} className="flex flex-col gap-1.5">
                  <Label>{fields[field]}</Label>
                  {isTextArea(field) ? (
                    <Textarea name={field} rows={4} defaultValue={(entityRecord[field] as string) ?? ""} />
                  ) : (
                    <Input name={field} type={inputType(field)} defaultValue={(entityRecord[field] as string) ?? ""} />
                  )}
                </div>
              ))}
              <p className="text-xs text-[#726c78]">Dein Claim ist bestätigt. Änderungen werden sofort veröffentlicht.</p>
              <div>
                <SubmitButton>Änderungen veröffentlichen</SubmitButton>
              </div>
            </form>
          </CardContent>
        </Card>
        {galleryOrigin && typeof entityRecord.photo_url === "string" && entityRecord.photo_url && (
          <div className="flex flex-col gap-4">
            <Separator />
            <div>
              <h2 className="mb-1 text-[15px] font-semibold text-[#15131a]">Runder Ausschnitt für App-Miniaturen</h2>
              <p className="mb-4 text-sm text-[#726c78]">Lege fest, welcher Bereich deines Hauptbilds in runden Profilbildern erscheint.</p>
              <AvatarCropButton
                entityType={`${galleryOrigin}s` as "persons" | "ensembles" | "venues"}
                entityId={entityId}
                photoUrl={entityRecord.photo_url as string}
                initialCrop={
                  entityRecord.avatar_crop_x != null &&
                  entityRecord.avatar_crop_y != null &&
                  entityRecord.avatar_crop_width != null &&
                  entityRecord.avatar_crop_height != null
                    ? {
                        x: Number(entityRecord.avatar_crop_x),
                        y: Number(entityRecord.avatar_crop_y),
                        width: Number(entityRecord.avatar_crop_width),
                        height: Number(entityRecord.avatar_crop_height),
                      }
                    : null
                }
                path={`/veranstalter/profile/${entityType}/${entityId}`}
              />
            </div>
          </div>
        )}
      </PageBody>
    </div>
  );
}
