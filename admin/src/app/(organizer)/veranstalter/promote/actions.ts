"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

const PLACEMENTS = new Set(["standard", "featured", "local_spotlight", "homepage_feature", "push"]);

export async function requestPromotion(formData: FormData) {
  const eventId = String(formData.get("event_id") ?? "").trim();
  const placement = String(formData.get("placement") ?? "").trim();
  const note = String(formData.get("requester_note") ?? "").trim();

  if (!eventId || !PLACEMENTS.has(placement)) throw new Error("Bitte wähle ein Event und eine Platzierung.");
  if (note.length > 1000) throw new Error("Die Nachricht darf höchstens 1.000 Zeichen lang sein.");

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet.");

  // RLS ist die verbindliche zweite Schranke. Diese Prüfung liefert der UI
  // aber eine klare Antwort, statt eine rohe Policy-Fehlermeldung zu zeigen.
  const { data: event } = await supabase
    .from("events")
    .select("id, organizer_id, status, start_datetime")
    .eq("id", eventId)
    .maybeSingle();
  if (!event || event.status !== "scheduled" || new Date(event.start_datetime as string).getTime() <= Date.now()) {
    throw new Error("Promotionen sind nur für kommende, veröffentlichte Events möglich.");
  }

  const { data: claim } = await supabase
    .from("entity_claims")
    .select("id")
    .eq("entity_type", "organizer")
    .eq("entity_id", event.organizer_id as string)
    .eq("user_id", user.id)
    .eq("status", "approved")
    .maybeSingle();
  if (!claim) throw new Error("Du bist für dieses Event nicht berechtigt.");

  const { error } = await supabase.from("event_promotions").insert({
    event_id: eventId,
    requested_by: user.id,
    placement,
    requester_note: note || null,
  });
  if (error) throw new Error(error.message);

  revalidatePath("/veranstalter/promote");
}
