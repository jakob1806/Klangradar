import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Field, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { ImageUploadField } from "@/components/image-upload-field";
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

  const { data: pendingSuggestion } = await supabase
    .from("entity_edit_suggestions")
    .select("id")
    .eq("entity_type", entityType)
    .eq("entity_id", entityId)
    .eq("user_id", user!.id)
    .eq("status", "pending")
    .maybeSingle();

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <h1 className="type-heading mb-2 text-2xl text-[#1d1d1f]">Profil bearbeiten</h1>
      <p className="mb-6 text-sm text-[#86868b]">{(entityRecord[nameColumn] as string) ?? ""}</p>

      {pendingSuggestion ? (
        <p className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          Eine Änderung ist bereits in Prüfung — bitte warte auf die Redaktionsentscheidung, bevor du eine
          neue vorschlägst.
        </p>
      ) : (
        <form action={submitEditSuggestion.bind(null, entityType, entityId)} className="flex flex-col gap-4">
          {fieldNames.map((field) => field === "social_links" ? (
            <div key={field} className="rounded-xl border border-black/[0.06] bg-white p-4"><p className="text-sm font-semibold text-[#1d1d1f]">Social Media</p><p className="mt-1 text-xs text-[#86868b]">Bitte vollständige Profil-Links mit https:// eintragen. In den Apps erscheinen später Icon und Plattformname, nie die rohe URL.</p><div className="mt-4 grid gap-3 sm:grid-cols-2">{SOCIAL_PLATFORMS.map((platform) => <Field key={platform} label={platform[0].toUpperCase() + platform.slice(1)}><TextInput name={`social_${platform}`} type="url" defaultValue={socialLinks[platform] ?? ""} placeholder={`https://www.${platform}.com/deinprofil`} /></Field>)}</div></div>
          ) : field === "gallery_urls" ? (
            <Field key={field} label="Galeriebilder"><TextArea name={field} rows={5} defaultValue={Array.isArray(entityRecord.gallery_urls) ? (entityRecord.gallery_urls as string[]).join("\n") : ""} placeholder={"Eine Bild-URL pro Zeile, z. B.\nhttps://…/konzertfoto-1.jpg\nhttps://…/konzertfoto-2.jpg"} /><p className="mt-1 text-xs text-[#86868b]">Diese Bilder erscheinen nach Freigabe in der öffentlichen Galerie.</p></Field>
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
          <p className="text-xs text-neutral-400">
            Deine Änderung wird von der Redaktion geprüft, bevor sie öffentlich sichtbar wird.
          </p>
          <div>
            <SubmitButton>Änderung vorschlagen</SubmitButton>
          </div>
        </form>
      )}
    </div>
  );
}
