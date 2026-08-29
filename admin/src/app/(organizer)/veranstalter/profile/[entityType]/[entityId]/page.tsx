import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Field, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
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
          {fieldNames.map((field) => (
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
