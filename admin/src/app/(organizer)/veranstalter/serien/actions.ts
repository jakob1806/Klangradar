"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function createEventSeries(_previousState: { error?: string; success?: true }, formData: FormData): Promise<{ error?: string; success?: true }> {
  const title = String(formData.get("title") ?? "").trim();
  const organizerId = String(formData.get("organizer_id") ?? "").trim();
  const description = String(formData.get("description_de") ?? "").trim() || null;
  const imageUrl = String(formData.get("image_url") ?? "").trim() || null;
  const eventIds = [...new Set(formData.getAll("event_ids").map(String).filter(Boolean))];

  if (!title || !organizerId) return { error: "Bitte gib einen Namen und die zugehörige Institution an." };
  if (title.length > 180) return { error: "Der Name darf höchstens 180 Zeichen haben." };
  if (eventIds.length === 0) return { error: "Wähle mindestens einen Termin aus." };
  if (imageUrl && !/^https:\/\//i.test(imageUrl)) return { error: "Bitte verwende für das Bild eine vollständige https-Adresse." };

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Bitte melde dich erneut an." };

  const { data: claim } = await supabase
    .from("entity_claims")
    .select("id")
    .eq("entity_type", "organizer")
    .eq("entity_id", organizerId)
    .eq("user_id", user.id)
    .eq("status", "approved")
    .maybeSingle();
  if (!claim) return { error: "Diese Institution darfst du nicht verwalten." };

  const { data: ownedEvents } = await supabase
    .from("events")
    .select("id")
    .eq("organizer_id", organizerId)
    .in("id", eventIds);
  if ((ownedEvents ?? []).length !== eventIds.length) return { error: "Mindestens ein ausgewählter Termin gehört nicht zu dieser Institution." };

  const { data: series, error: seriesError } = await supabase
    .from("event_series")
    .insert({ organizer_id: organizerId, title, description_de: description, image_url: imageUrl, created_by: user.id })
    .select("id")
    .single();
  if (seriesError || !series) return { error: seriesError?.message ?? "Serie konnte nicht angelegt werden." };

  const { error: updateError } = await supabase
    .from("events")
    .update({ series_id: series.id, updated_at: new Date().toISOString() })
    .in("id", eventIds)
    .eq("organizer_id", organizerId);
  if (updateError) return { error: updateError.message };

  revalidatePath("/veranstalter/serien");
  revalidatePath("/veranstalter/events");
  return { success: true };
}
