"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { EDITABLE_FIELDS_FOR_ENTITY_TYPE, TABLE_FOR_ENTITY_TYPE, type ClaimableEntityType } from "@/lib/entity-tables";

// Ein bestätigter Claim ist eine echte Verwaltungsberechtigung. Die RLS-
// Policies der Live-Edit-Migration prüfen den Anspruch zusätzlich direkt in
// der Datenbank, damit der Server Action nicht vertraut werden muss.
export async function submitEditSuggestion(entityType: ClaimableEntityType, entityId: string, formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet");

  const fields: Record<string, string> = EDITABLE_FIELDS_FOR_ENTITY_TYPE[entityType];
  const proposedChanges: Record<string, unknown> = {};
  for (const field of Object.keys(fields)) {
    if (field === "social_links") {
      const social = Object.fromEntries(["instagram", "facebook", "youtube", "spotify", "tiktok", "linkedin"].map((platform) => [platform, String(formData.get(`social_${platform}`) ?? "").trim()]).filter(([, url]) => url));
      proposedChanges[field] = social;
    } else if (field === "gallery_urls") {
      // Die echte Galerie liegt in images und wird über GalleryEditor direkt
      // gespeichert (Upload, Reihenfolge, Zuschnitt). Keine alte URL-Liste
      // in die Stammdaten zurückschreiben.
      continue;
    } else if (field === "founded_year" || field === "member_count") {
      const value = String(formData.get(field) ?? "").trim();
      proposedChanges[field] = value ? Number(value) : null;
    } else {
      proposedChanges[field] = String(formData.get(field) ?? "").trim() || null;
    }
  }

  const { error } = await supabase
    .from(TABLE_FOR_ENTITY_TYPE[entityType])
    .update(proposedChanges)
    .eq("id", entityId);
  if (error) {
    throw new Error(error.message);
  }

  revalidatePath(`/veranstalter/profile/${entityType}/${entityId}`);
  revalidatePath("/veranstalter/bibliothek");
  redirect("/veranstalter");
}
