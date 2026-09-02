"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

/** Zusätzlichen Ticketanbieter ergänzen (Ticket Intelligence: "Mehrere
 * Ticketanbieter pro Event unterstützen") — die Domain wird serverseitig
 * per admin_add_ticket_link() aus der URL abgeleitet, damit dieselbe Logik
 * wie beim automatischen Sync aus events.ticket_url gilt (siehe
 * 20261016000017_multi_ticket_providers.sql). */
export async function addTicketLink(eventId: string, formData: FormData) {
  const supabase = await createClient();
  const url = String(formData.get("url") ?? "").trim();
  if (!url) return { error: "Bitte eine URL angeben." };

  const priceMinRaw = String(formData.get("price_min") ?? "").trim();
  const priceMaxRaw = String(formData.get("price_max") ?? "").trim();

  const { error } = await supabase.rpc("admin_add_ticket_link", {
    p_event_id: eventId,
    p_url: url,
    p_price_min: priceMinRaw ? Number(priceMinRaw) : null,
    p_price_max: priceMaxRaw ? Number(priceMaxRaw) : null,
  });
  if (error) return { error: error.message };

  const discounts = formData.getAll("discount_categories").map(String);
  const availability = String(formData.get("availability_status") ?? "unknown");
  const { error: detailError } = await supabase.from("event_ticket_links").update({
    availability_status: availability,
    discount_categories: discounts,
    discount_notes: String(formData.get("discount_notes") ?? "").trim() || null,
    price_updated_at: new Date().toISOString(),
    availability_updated_at: new Date().toISOString(),
  }).eq("event_id", eventId).eq("url", url);
  if (detailError) return { error: detailError.message };

  revalidatePath(`/events/${eventId}`);
  return {};
}

export async function removeTicketLink(eventId: string, url: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_remove_ticket_link", { p_event_id: eventId, p_url: url });
  if (error) throw new Error(error.message);
  revalidatePath(`/events/${eventId}`);
}
