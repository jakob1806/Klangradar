"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type RosterActionState = { error?: string; success?: true };

export async function addRosterEntry(_state: RosterActionState, formData: FormData): Promise<RosterActionState> {
  const organizerId = String(formData.get("organizer_id") ?? "");
  const entityType = String(formData.get("entity_type") ?? "");
  const entityId = String(formData.get("entity_id") ?? "");
  if (!organizerId || !entityId || !["person", "ensemble"].includes(entityType)) return { error: "Bitte wähle Agentur und Profil aus." };
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Bitte melde dich erneut an." };
  const { error } = await supabase.from("organizer_agency_roster").insert({ organizer_id: organizerId, entity_type: entityType, entity_id: entityId, added_by: user.id });
  if (error) return { error: error.code === "23505" ? "Dieses Profil ist bereits im Roster." : error.message };
  revalidatePath("/veranstalter/agentur");
  return { success: true } as const;
}

export async function removeRosterEntry(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("organizer_agency_roster").delete().eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/agentur");
}
