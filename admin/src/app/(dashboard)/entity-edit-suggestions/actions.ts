"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";
import { TABLE_FOR_ENTITY_TYPE, type ClaimableEntityType } from "@/lib/entity-tables";

// Wendet den gespeicherten jsonb-Patch direkt auf die Zieltabelle an — im
// Unterschied zu approveEntityClaim (reiner Status-Flip) muss hier
// tatsächlich geschrieben werden, deshalb zuerst die Suggestion laden.
export async function approveEntityEditSuggestion(suggestionId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: suggestion, error: fetchError } = await supabase
    .from("entity_edit_suggestions")
    .select("entity_type, entity_id, proposed_changes")
    .eq("id", suggestionId)
    .maybeSingle();
  if (fetchError || !suggestion) throw new Error(fetchError?.message ?? "Vorschlag nicht gefunden");

  const entityType = suggestion.entity_type as ClaimableEntityType;
  const { error: applyError } = await supabase
    .from(TABLE_FOR_ENTITY_TYPE[entityType])
    .update(suggestion.proposed_changes as Record<string, unknown>)
    .eq("id", suggestion.entity_id);
  if (applyError) throw new Error(applyError.message);

  const { error } = await supabase
    .from("entity_edit_suggestions")
    .update({ status: "approved", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", suggestionId);
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "entity_edit_suggestion",
    entityId: suggestionId,
    action: "approved",
    actor: user?.email ?? user?.id ?? "unknown",
    after: suggestion.proposed_changes,
  });

  revalidatePath("/entity-edit-suggestions");
}

export async function rejectEntityEditSuggestion(suggestionId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase
    .from("entity_edit_suggestions")
    .update({ status: "rejected", reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString() })
    .eq("id", suggestionId);
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "entity_edit_suggestion",
    entityId: suggestionId,
    action: "rejected",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/entity-edit-suggestions");
}
