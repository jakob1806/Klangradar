"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { EDITABLE_FIELDS_FOR_ENTITY_TYPE, type ClaimableEntityType } from "@/lib/entity-tables";

// Legt IMMER nur einen Vorschlag an, schreibt nie direkt in
// organizers/venues/persons/ensembles — eine geclaimte Stammdaten-Zeile
// bleibt redaktionell kuratiert (siehe entity_edit_suggestions-Migration).
// RLS ("Veranstalter schlägt Profiländerung für eigene Entität vor")
// verifiziert has_approved_claim serverseitig ohnehin nochmal — die Prüfung
// hier ist nur für eine verständliche Fehlermeldung statt einer rohen
// RLS-Ablehnung.
export async function submitEditSuggestion(entityType: ClaimableEntityType, entityId: string, formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet");

  const fields: Record<string, string> = EDITABLE_FIELDS_FOR_ENTITY_TYPE[entityType];
  const proposedChanges: Record<string, string | null> = {};
  for (const field of Object.keys(fields)) {
    proposedChanges[field] = String(formData.get(field) ?? "").trim() || null;
  }

  const { error } = await supabase.from("entity_edit_suggestions").insert({
    entity_type: entityType,
    entity_id: entityId,
    user_id: user.id,
    proposed_changes: proposedChanges,
  });
  if (error) {
    // Partial-Unique-Index (entity_type, entity_id, user_id) where status='pending'
    if (error.code === "23505") {
      throw new Error("Du hast für dieses Profil bereits eine Änderung in Prüfung.");
    }
    throw new Error(error.message);
  }

  revalidatePath("/veranstalter");
  redirect("/veranstalter");
}
