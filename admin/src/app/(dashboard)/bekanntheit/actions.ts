"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (29.10.2026): Bekanntheit manuell anpassen. Der
// Wert wird zum Wikipedia-Score addiert; −10 blendet aus den Vorschlägen aus.
export async function setProminenceBoost(kind: string, entityId: string, boost: number, formData?: FormData) {
  const supabase = await createClient();
  const note = formData ? String(formData.get("note") ?? "") : null;
  const { error } = await supabase.rpc("admin_set_prominence_boost", {
    p_kind: kind,
    p_entity_id: entityId,
    p_boost: boost,
    p_note: note,
  });
  if (error) throw new Error(error.message);
  revalidatePath("/bekanntheit");
}
