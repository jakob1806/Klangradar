"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

async function ownedOrganizerIds() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet.");
  const { data } = await supabase.from("entity_claims").select("entity_id").eq("user_id", user.id).eq("entity_type", "organizer").eq("status", "approved");
  return { supabase, user, ids: (data ?? []).map((row) => row.entity_id as string) };
}

export async function createEventSeries(formData: FormData) {
  const title = String(formData.get("title") ?? "").trim();
  const organizerId = String(formData.get("organizer_id") ?? "");
  const description = String(formData.get("description_de") ?? "").trim();
  if (!title || title.length > 160) throw new Error("Bitte gib einen Serientitel mit höchstens 160 Zeichen ein.");
  const { supabase, user, ids } = await ownedOrganizerIds();
  if (!ids.includes(organizerId)) throw new Error("Ungültige Institution.");
  const { error } = await supabase.from("event_series").insert({ organizer_id: organizerId, title, description_de: description || null, created_by: user.id });
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/series");
}

export async function assignEventToSeries(eventId: string, seriesId: string | null) {
  const { supabase, ids } = await ownedOrganizerIds();
  const { data: event } = await supabase.from("events").select("organizer_id").eq("id", eventId).maybeSingle();
  if (!event?.organizer_id || !ids.includes(event.organizer_id as string)) throw new Error("Du bist für dieses Event nicht berechtigt.");
  if (seriesId) {
    const { data: series } = await supabase.from("event_series").select("organizer_id").eq("id", seriesId).maybeSingle();
    if (!series || series.organizer_id !== event.organizer_id) throw new Error("Die Serie muss zur selben Institution gehören.");
  }
  const { error } = await supabase.from("events").update({ series_id: seriesId, updated_at: new Date().toISOString() }).eq("id", eventId);
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/series");
}
