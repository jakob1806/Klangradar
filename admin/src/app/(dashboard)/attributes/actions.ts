"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function saveAttribute(formData: FormData) {
  const supabase = await createClient();
  const id = String(formData.get("id") ?? "");
  const payload = {
    slug: String(formData.get("slug") ?? "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "_"),
    label_de: String(formData.get("label_de") ?? "").trim(),
    group_key: String(formData.get("group_key") ?? "thema").trim(),
    inspiration_title: String(formData.get("inspiration_title") ?? "").trim() || null,
    inspiration_enabled: formData.get("inspiration_enabled") === "on",
    icon_name: String(formData.get("icon_name") ?? "").trim() || null,
    color_key: String(formData.get("color_key") ?? "accent"),
    sort_order: Number(formData.get("sort_order") ?? 0),
  };
  if (!payload.slug || !payload.label_de) throw new Error("Slug und Name sind erforderlich.");
  const query = id ? supabase.from("attributes").update(payload).eq("id", id) : supabase.from("attributes").insert(payload);
  const { error } = await query;
  if (error) throw new Error(error.message);
  revalidatePath("/attributes");
}

export async function assignAttribute(formData: FormData) {
  const supabase = await createClient();
  const entityType = String(formData.get("entity_type"));
  const entityId = String(formData.get("entity_id") ?? "").trim();
  const attributeId = String(formData.get("attribute_id") ?? "");
  const weight = Math.max(0.01, Math.min(1, Number(formData.get("weight") ?? 1)));
  const config: Record<string, { table: string; key: string }> = {
    event: { table: "event_attributes", key: "event_id" },
    work: { table: "work_attributes", key: "work_id" },
    person: { table: "person_attributes", key: "person_id" },
    ensemble: { table: "ensemble_attributes", key: "ensemble_id" },
    venue: { table: "venue_attributes", key: "venue_id" },
  };
  const target = config[entityType];
  if (!target || !entityId || !attributeId) throw new Error("Ungültige Zuordnung.");
  const { error } = await supabase.from(target.table).upsert({
    [target.key]: entityId, attribute_id: attributeId, weight, source: "editorial",
  });
  if (error) throw new Error(error.message);
  revalidatePath("/attributes");
}

export async function deleteAttribute(attributeId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("attributes").delete().eq("id", attributeId);
  if (error) throw new Error(error.message);
  revalidatePath("/attributes");
}

export async function removeAssignment(entityType: string, entityId: string, attributeId: string) {
  const supabase = await createClient();
  const config: Record<string, { table: string; key: string }> = {
    event: { table: "event_attributes", key: "event_id" }, work: { table: "work_attributes", key: "work_id" },
    person: { table: "person_attributes", key: "person_id" }, ensemble: { table: "ensemble_attributes", key: "ensemble_id" },
    venue: { table: "venue_attributes", key: "venue_id" },
  };
  const target = config[entityType];
  if (!target) throw new Error("Ungültiger Entitätstyp.");
  const { error } = await supabase.from(target.table).delete().eq(target.key, entityId).eq("attribute_id", attributeId);
  if (error) throw new Error(error.message);
  revalidatePath("/attributes");
}
