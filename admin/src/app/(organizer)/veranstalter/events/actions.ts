"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { munichLocalToISOString } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";

type EventActionResult = { error?: string };

function readEventFields(formData: FormData) {
  // datetime-local enthält absichtlich keine Zone. Server Actions laufen auf
  // Vercel in UTC; deshalb ausdrücklich als Münchner Zeit interpretieren.
  const startLocal = String(formData.get("start_datetime") ?? "");

  return {
    slug: String(formData.get("slug") ?? "").trim(),
    title: String(formData.get("title") ?? "").trim(),
    subtitle: String(formData.get("subtitle") ?? "").trim() || null,
    description_de: String(formData.get("description_de") ?? "").trim() || null,
    start_datetime: startLocal ? munichLocalToISOString(startLocal) : null,
    duration_minutes: formData.get("duration_minutes") ? Number(formData.get("duration_minutes")) : null,
    has_intermission: formData.get("has_intermission") === "on",
    venue_id: String(formData.get("venue_id") ?? ""),
    venue_detail: String(formData.get("venue_detail") ?? "").trim() || null,
    organizer_id: String(formData.get("organizer_id") ?? ""),
    ticket_url: String(formData.get("ticket_url") ?? "").trim() || null,
    price_min: formData.get("price_min") ? Number(formData.get("price_min")) : null,
    price_max: formData.get("price_max") ? Number(formData.get("price_max")) : null,
    is_free: formData.get("is_free") === "on",
    remaining_tickets_status: String(formData.get("remaining_tickets_status") ?? "").trim() || null,
    doors_info: String(formData.get("doors_info") ?? "").trim() || null,
    age_restriction: String(formData.get("age_restriction") ?? "").trim() || null,
    discount_info: String(formData.get("discount_info") ?? "").trim() || null,
    presale_fee_info: String(formData.get("presale_fee_info") ?? "").trim() || null,
    genreIds: formData.getAll("genre_ids").map(String),
    newGenres: formData.getAll("new_genres").map(String).map((value) => value.trim()).filter(Boolean),
  };
}

function genreSlug(value: string) {
  return value
    .toLocaleLowerCase("de")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

async function ensureNewGenres(supabase: Awaited<ReturnType<typeof createClient>>, labels: string[]) {
  const ids: string[] = [];
  for (const label of [...new Set(labels)]) {
    const slug = genreSlug(label);
    if (!slug) continue;
    const { data, error } = await supabase
      .from("genres")
      .upsert({ slug, label_de: label }, { onConflict: "slug", ignoreDuplicates: true })
      .select("id")
      .maybeSingle();
    if (error) throw new Error(`Genre „${label}“ konnte nicht angelegt werden: ${error.message}`);
    if (data?.id) ids.push(data.id);
    else {
      const { data: existing } = await supabase.from("genres").select("id").eq("slug", slug).single();
      if (existing?.id) ids.push(existing.id);
    }
  }
  return ids;
}

async function syncGenres(supabase: Awaited<ReturnType<typeof createClient>>, eventId: string, genreIds: string[]) {
  await supabase.from("event_genres").delete().eq("event_id", eventId);
  if (genreIds.length > 0) {
    await supabase.from("event_genres").insert(genreIds.map((genre_id) => ({ event_id: eventId, genre_id })));
  }
}

export async function createOrganizerEvent(formData: FormData): Promise<EventActionResult> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return { error: "Bitte melde dich erneut an." };

    const f = readEventFields(formData);

  // organizer_id NIE aus dem Formular vertrauen — serverseitig gegen die
  // eigenen genehmigten Claims verifizieren, statt sich auf die
  // RLS-Ablehnung allein zu verlassen (freundliche Fehlermeldung statt
  // einer rohen Postgres-Policy-Verletzung).
    const approvedOrganizerIds = (await getEventOrganizerOptions()).map((organizer) => organizer.id);
    if (approvedOrganizerIds.length === 0) {
      return { error: "Du hast noch kein genehmigtes Profil. Bitte beanspruche zuerst eine Institution, Venue, Person oder ein Ensemble." };
    }
    if (!approvedOrganizerIds.includes(f.organizer_id)) {
      return { error: "Bitte wähle eines deiner genehmigten Profile aus." };
    }

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
      venue_detail: f.venue_detail,
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
      status: "draft",
    })
    .select("id")
    .single();

    if (error || !data) return { error: "Das Event konnte nicht angelegt werden. Bitte prüfe die Pflichtfelder und versuche es erneut." };

    const newGenreIds = await ensureNewGenres(supabase, f.newGenres);
    await syncGenres(supabase, data.id, [...new Set([...f.genreIds, ...newGenreIds])]);

    revalidatePath("/veranstalter/events");
    redirect("/veranstalter/events");
  } catch (cause) {
    // redirect() wird von Next intern als Sonderfall geworfen und muss
    // unverändert weitergereicht werden. Alle tatsächlichen Fehler werden
    // im Formular angezeigt statt eine vollständige Fehlerseite zu erzeugen.
    if (cause && typeof cause === "object" && "digest" in cause) throw cause;
    console.error("Organizer event creation failed", cause);
    return { error: "Das Event konnte gerade nicht angelegt werden. Bitte versuche es gleich noch einmal." };
  }
}

export async function updateOrganizerEvent(eventId: string, formData: FormData): Promise<EventActionResult> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return { error: "Bitte melde dich erneut an." };

    const f = readEventFields(formData);

    const approvedOrganizerIds = (await getEventOrganizerOptions()).map((organizer) => organizer.id);
    const { data: existing } = await supabase.from("events").select("organizer_id").eq("id", eventId).maybeSingle();
    const ownsOrganizer = Boolean(existing?.organizer_id && approvedOrganizerIds.includes(existing.organizer_id));
    const { data: hasClaimedProfileAccess } = await supabase.rpc("has_claimed_profile_event_edit_access", { p_event_id: eventId });
    if (!ownsOrganizer && !hasClaimedProfileAccess) {
      return { error: "Du bist für dieses Event nicht berechtigt." };
    }
    if (ownsOrganizer && !approvedOrganizerIds.includes(f.organizer_id)) {
      return { error: "Bitte wähle eines deiner genehmigten Profile aus." };
    }

  // Bewusst KEIN status-Feld im Patch — Veranstalter dürfen alle anderen
  // Felder frei ändern (auch nach Veröffentlichung, sofort sichtbar), der
  // Trigger events_organizer_status_guard verwirft ohnehin jede
  // status-Änderung durch Nicht-Redaktion.
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
      venue_detail: f.venue_detail,
      // Bei einem Event eines geclaimten Künstlers bleibt die Institution,
      // die das Event ursprünglich veranstaltet, unangetastet.
      organizer_id: ownsOrganizer ? f.organizer_id : existing?.organizer_id,
      ticket_url: f.ticket_url,
      price_min: f.price_min,
      price_max: f.price_max,
      is_free: f.is_free,
      remaining_tickets_status: f.remaining_tickets_status,
      doors_info: f.doors_info,
      age_restriction: f.age_restriction,
      discount_info: f.discount_info,
      presale_fee_info: f.presale_fee_info,
      updated_at: new Date().toISOString(),
    })
    .eq("id", eventId);

    if (error) return { error: "Die Änderungen konnten nicht gespeichert werden. Bitte versuche es erneut." };

    const newGenreIds = await ensureNewGenres(supabase, f.newGenres);
    await syncGenres(supabase, eventId, [...new Set([...f.genreIds, ...newGenreIds])]);

    revalidatePath("/veranstalter/events");
    redirect("/veranstalter/events");
  } catch (cause) {
    if (cause && typeof cause === "object" && "digest" in cause) throw cause;
    console.error("Organizer event update failed", cause);
    return { error: "Die Änderungen konnten gerade nicht gespeichert werden. Bitte versuche es gleich noch einmal." };
  }
}

export async function addOrganizerEventImage(eventId: string, imageUrl: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet.");
  const expectedPrefix = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/entity-photos/organizer-event-images/${user.id}/`;
  if (!imageUrl.startsWith(expectedPrefix)) throw new Error("Ungültige Bildquelle.");
  const approvedOrganizerIds = (await getEventOrganizerOptions()).map((organizer) => organizer.id);
  const { data: event } = await supabase.from("events").select("organizer_id, image_urls").eq("id", eventId).maybeSingle();
  if (!event) throw new Error("Das Event wurde nicht gefunden oder ist nicht zugänglich.");
  const ownsOrganizer = Boolean(event?.organizer_id && approvedOrganizerIds.includes(event.organizer_id as string));
  const { data: hasClaimedProfileAccess } = await supabase.rpc("has_claimed_profile_event_edit_access", { p_event_id: eventId });
  if (!ownsOrganizer && !hasClaimedProfileAccess) throw new Error("Du bist für dieses Event nicht berechtigt.");
  const images = [...new Set([...(event.image_urls as string[] | null ?? []), imageUrl])];
  const { error } = await supabase.from("events").update({ image_urls: images, updated_at: new Date().toISOString() }).eq("id", eventId);
  if (error) throw new Error(error.message);
  revalidatePath(`/veranstalter/events/${eventId}`);
  revalidatePath("/veranstalter/events");
}
