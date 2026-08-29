"use server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function createAgency(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim(); const website = String(formData.get("website_url") ?? "").trim();
  if (!name || name.length > 160) throw new Error("Bitte gib einen Namen mit höchstens 160 Zeichen ein.");
  const supabase = await createClient(); const { data: { user } } = await supabase.auth.getUser(); if (!user) throw new Error("Nicht angemeldet.");
  const { data, error } = await supabase.from("agencies").insert({ name, website_url: website || null, created_by: user.id }).select("id").single(); if (error || !data) throw new Error(error?.message ?? "Anlegen fehlgeschlagen.");
  const { error: memberError } = await supabase.from("agency_members").insert({ agency_id: data.id, user_id: user.id, role: "owner" }); if (memberError) throw new Error(memberError.message);
  revalidatePath("/veranstalter/agency");
}

export async function addRosterEntry(formData: FormData) {
  const agencyId = String(formData.get("agency_id") ?? ""); const entityType = String(formData.get("entity_type") ?? ""); const entityId = String(formData.get("entity_id") ?? "");
  if (!agencyId || !entityId || !["person", "ensemble"].includes(entityType)) throw new Error("Ungültiger Roster-Eintrag.");
  const supabase = await createClient(); const { error } = await supabase.from("agency_roster").insert({ agency_id: agencyId, entity_type: entityType, entity_id: entityId }); if (error) throw new Error(error.message); revalidatePath("/veranstalter/agency");
}
