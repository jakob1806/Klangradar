"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readEventFields(formData: FormData) {
  // Nimmt an, dass die Browser-Zeitzone der Redakteurin Europe/Berlin ist —
  // datetime-local liefert keine Zeitzone mit, new Date() interpretiert sie
  // als lokale Zeit des Browsers.
  const startLocal = String(formData.get("start_datetime") ?? "");

  return {
    slug: String(formData.get("slug") ?? "").trim(),
    title: String(formData.get("title") ?? "").trim(),
    subtitle: String(formData.get("subtitle") ?? "").trim() || null,
    description_de: String(formData.get("description_de") ?? "").trim() || null,
    start_datetime: startLocal ? new Date(startLocal).toISOString() : null,
    duration_minutes: formData.get("duration_minutes")
      ? Number(formData.get("duration_minutes"))
      : null,
    has_intermission: formData.get("has_intermission") === "on",
    venue_id: String(formData.get("venue_id") ?? ""),
    organizer_id: String(formData.get("organizer_id") ?? "") || null,
    ticket_url: String(formData.get("ticket_url") ?? "").trim() || null,
    price_min: formData.get("price_min") ? Number(formData.get("price_min")) : null,
    price_max: formData.get("price_max") ? Number(formData.get("price_max")) : null,
    is_free: formData.get("is_free") === "on",
    remaining_tickets_status: String(formData.get("remaining_tickets_status") ?? "").trim() || null,
    doors_info: String(formData.get("doors_info") ?? "").trim() || null,
    age_restriction: String(formData.get("age_restriction") ?? "").trim() || null,
    discount_info: String(formData.get("discount_info") ?? "").trim() || null,
    presale_fee_info: String(formData.get("presale_fee_info") ?? "").trim() || null,
    status: String(formData.get("status") ?? "scheduled"),
    genreIds: formData.getAll("genre_ids").map(String),
  };
}

async function syncGenres(
  supabase: Awaited<ReturnType<typeof createClient>>,
  eventId: string,
  genreIds: string[],
) {
  await supabase.from("event_genres").delete().eq("event_id", eventId);
  if (genreIds.length > 0) {
    await supabase
      .from("event_genres")
      .insert(genreIds.map((genre_id) => ({ event_id: eventId, genre_id })));
  }
}

export async function createEvent(formData: FormData) {
  const f = readEventFields(formData);
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("events")
    .insert({
      slug: f.slug,
      title: f.title,
      subtitle: f.subtitle,
      description_de: f.description_de,
      start_datetime: f.start_datetime,
      duration_minutes: f.duration_minutes,
      has_intermission: f.has_intermission,
      venue_id: f.venue_id,
      organizer_id: f.organizer_id,
      ticket_url: f.ticket_url,
      price_min: f.price_min,
      price_max: f.price_max,
      is_free: f.is_free,
      remaining_tickets_status: f.remaining_tickets_status,
      doors_info: f.doors_info,
      age_restriction: f.age_restriction,
      discount_info: f.discount_info,
      presale_fee_info: f.presale_fee_info,
      status: f.status,
    })
    .select("id")
    .single();

  if (error) throw new Error(error.message);

  await syncGenres(supabase, data.id, f.genreIds);

  revalidatePath("/events");
  redirect("/events");
}

export async function updateEvent(eventId: string, formData: FormData) {
  const f = readEventFields(formData);
  const supabase = await createClient();

  const { error } = await supabase
    .from("events")
    .update({
      slug: f.slug,
      title: f.title,
      subtitle: f.subtitle,
      description_de: f.description_de,
      start_datetime: f.start_datetime,
      duration_minutes: f.duration_minutes,
      has_intermission: f.has_intermission,
      venue_id: f.venue_id,
      organizer_id: f.organizer_id,
      ticket_url: f.ticket_url,
      price_min: f.price_min,
      price_max: f.price_max,
      is_free: f.is_free,
      remaining_tickets_status: f.remaining_tickets_status,
      doors_info: f.doors_info,
      age_restriction: f.age_restriction,
      discount_info: f.discount_info,
      presale_fee_info: f.presale_fee_info,
      status: f.status,
      updated_at: new Date().toISOString(),
    })
    .eq("id", eventId);

  if (error) throw new Error(error.message);

  await syncGenres(supabase, eventId, f.genreIds);

  revalidatePath("/events");
  redirect("/events");
}

export async function deleteEvent(eventId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("events").delete().eq("id", eventId);
  if (error) throw new Error(error.message);

  revalidatePath("/events");
  redirect("/events");
}
