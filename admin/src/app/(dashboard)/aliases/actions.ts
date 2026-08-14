"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type AliasEntityType = "person" | "ensemble" | "venue" | "work";

const ENTITY_CONFIG: Record<AliasEntityType, { table: string; nameColumn: string }> = {
  person: { table: "persons", nameColumn: "full_name" },
  ensemble: { table: "ensembles", nameColumn: "name" },
  venue: { table: "venues", nameColumn: "name" },
  work: { table: "works", nameColumn: "title" },
};

function entityType(value: FormDataEntryValue | null): AliasEntityType {
  const type = String(value ?? "");
  if (!(type in ENTITY_CONFIG)) throw new Error("Unbekannter Entitätstyp.");
  return type as AliasEntityType;
}

export async function addEntityAlias(formData: FormData) {
  const type = entityType(formData.get("entity_type"));
  const entityId = String(formData.get("entity_id") ?? "");
  const alias = String(formData.get("alias") ?? "").replace(/\s+/g, " ").trim();
  if (!entityId || !alias) throw new Error("Alias und Ziel sind erforderlich.");

  const supabase = await createClient();
  const { error } = await supabase.from("entity_aliases").insert({
    entity_type: type,
    entity_id: entityId,
    alias,
  });
  if (error) throw new Error(error.message);
  revalidatePath("/aliases");
}

export async function deleteEntityAlias(formData: FormData) {
  const aliasId = String(formData.get("alias_id") ?? "");
  if (!aliasId) return;
  const supabase = await createClient();
  const { error } = await supabase.from("entity_aliases").delete().eq("id", aliasId);
  if (error) throw new Error(error.message);
  revalidatePath("/aliases");
}

export async function setCanonicalEntityName(formData: FormData) {
  const type = entityType(formData.get("entity_type"));
  const entityId = String(formData.get("entity_id") ?? "");
  const canonicalName = String(formData.get("canonical_name") ?? "").replace(/\s+/g, " ").trim();
  if (!entityId || !canonicalName) throw new Error("Die Hauptschreibweise darf nicht leer sein.");

  const supabase = await createClient();
  let patch: Record<string, unknown> = { [ENTITY_CONFIG[type].nameColumn]: canonicalName };
  if (type === "person") {
    const parts = canonicalName.split(" ");
    patch = {
      ...patch,
      first_name: parts[0],
      middle_name: parts.length > 2 ? parts.slice(1, -1).join(" ") : null,
      last_name: parts.length > 1 ? parts.at(-1) : "",
      updated_at: new Date().toISOString(),
    };
  }
  const { error } = await supabase.from(ENTITY_CONFIG[type].table).update(patch).eq("id", entityId);
  if (error) throw new Error(error.message);
  revalidatePath("/aliases");
  revalidatePath("/persons");
  revalidatePath("/ensembles");
  revalidatePath("/venues");
}
