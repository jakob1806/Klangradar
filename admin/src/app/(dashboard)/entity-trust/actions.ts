"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";
import type { ClaimableEntityType } from "@/lib/entity-tables";

export async function setTrustLevel(entityType: ClaimableEntityType, entityId: string, level: "verified" | "official") {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase
    .from("entity_trust_overrides")
    .upsert(
      { entity_type: entityType, entity_id: entityId, level, set_by: user?.id ?? null, set_at: new Date().toISOString() },
      { onConflict: "entity_type,entity_id" },
    );
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "entity_trust_override",
    entityId,
    action: `set_${level}`,
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/entity-trust");
}

// Zurück auf "claimed"/"unverified" — beides ergibt sich rein aus
// entity_claims, deshalb reicht das Löschen der Override-Zeile.
export async function clearTrustLevel(entityType: ClaimableEntityType, entityId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase
    .from("entity_trust_overrides")
    .delete()
    .eq("entity_type", entityType)
    .eq("entity_id", entityId);
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, {
    entityType: "entity_trust_override",
    entityId,
    action: "cleared",
    actor: user?.email ?? user?.id ?? "unknown",
  });

  revalidatePath("/entity-trust");
}
