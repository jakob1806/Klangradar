"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { munichLocalToISOString } from "@/lib/munich-time";
import { cleanupEventGroupIfEmpty } from "@/lib/event-group-cleanup";

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
    newGenres: formData.getAll("new_genres").map(String).map((value) => value.trim()).filter(Boolean),
  };
}

function genreSlug(value: string) {
  return value.toLocaleLowerCase("de").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

async function ensureNewGenres(supabase: Awaited<ReturnType<typeof createClient>>, labels: string[]) {
  const ids: string[] = [];
  for (const label of [...new Set(labels)]) {
    const slug = genreSlug(label);
    if (!slug) continue;
    const { data, error } = await supabase.from("genres").upsert(
      { slug, label_de: label },
      { onConflict: "slug", ignoreDuplicates: true },
    ).select("id").maybeSingle();
    if (error) throw new Error(`Genre „${label}“ konnte nicht angelegt werden: ${error.message}`);
    if (data?.id) ids.push(data.id);
    else {
      const { data: existing } = await supabase.from("genres").select("id").eq("slug", slug).single();
      if (existing?.id) ids.push(existing.id);
    }
  }
  return ids;
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

  const newGenreIds = await ensureNewGenres(supabase, f.newGenres);
  await syncGenres(supabase, data.id, [...new Set([...f.genreIds, ...newGenreIds])]);

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

  const newGenreIds = await ensureNewGenres(supabase, f.newGenres);
  await syncGenres(supabase, eventId, [...new Set([...f.genreIds, ...newGenreIds])]);

  revalidatePath("/events");
  redirect("/events");
}

/** Setzt mehrere Entwürfe in einem Rutsch auf status='scheduled' — bisher
 * ging das nur einzeln über das Bearbeiten-Formular. Der `.eq("status",
 * "draft")`-Filter ist eine bewusste Sicherheitsschranke: selbst wenn im
 * "Alle"-Tab aus Versehen auch nicht-draft-Zeilen mit ausgewählt werden
 * (z.B. bereits abgesagte/verschobene Events), ändert dieser Aufruf nur
 * tatsächliche Entwürfe — kein versehentliches Zurücksetzen anderer
 * Status. */
export async function bulkPublishEvents(
  eventIds: string[],
): Promise<{ updated: number; error?: string }> {
  if (eventIds.length === 0) return { updated: 0 };
  const supabase = await createClient();

  // .select("id") statt eventIds.length zurückzugeben — der .eq("status",
  // "draft")-Filter kann Zeilen stillschweigend überspringen (s.o.), sonst
  // meldet die UI mehr "veröffentlicht" als tatsächlich geändert wurden.
  const { data, error } = await supabase
    .from("events")
    .update({ status: "scheduled", updated_at: new Date().toISOString() })
    .in("id", eventIds)
    .eq("status", "draft")
    .select("id");

  if (error) return { updated: 0, error: error.message };

  revalidatePath("/events");
  return { updated: data?.length ?? 0 };
}

/** Einzelnen Entwurf ohne Auswahl/Bulk-Bar direkt veröffentlichen — Klick
 * pro Zeile statt "Checkbox anhaken → Bulk-Button klicken" für den
 * Standardfall "genau ein Entwurf soll jetzt live gehen". */
export async function publishEvent(eventId: string): Promise<{ error?: string }> {
  const supabase = await createClient();

  const { error } = await supabase
    .from("events")
    .update({ status: "scheduled", updated_at: new Date().toISOString() })
    .eq("id", eventId)
    .eq("status", "draft");

  if (error) return { error: error.message };

  revalidatePath("/events");
  return {};
}

/** Wendet nur die Felder an, die im Formular explizit über eine "Übernehmen"-
 * Checkbox markiert wurden (siehe bulk-edit-form.tsx) — ein leeres Feld ist
 * sonst nicht eindeutig "nicht ändern" vs. "auf leer setzen". Genres werden
 * nur ersetzt, wenn die Genre-Übernehmen-Checkbox gesetzt ist (leere Auswahl
 * dabei ist gültig: "alle Genres entfernen"). */
export async function bulkUpdateEvents(
  eventIds: string[],
  formData: FormData,
): Promise<{ updated: number; error?: string }> {
  if (eventIds.length === 0) return { updated: 0 };
  const supabase = await createClient();

  const patch: Record<string, unknown> = {};
  const applyText = (field: string) => {
    if (formData.get(`apply_${field}`) !== "on") return;
    const value = String(formData.get(field) ?? "").trim();
    patch[field] = value || null;
  };
  const applyNumber = (field: string) => {
    if (formData.get(`apply_${field}`) !== "on") return;
    const raw = String(formData.get(field) ?? "").trim();
    patch[field] = raw ? Number(raw) : null;
  };

  if (formData.get("apply_venue_id") === "on") patch.venue_id = String(formData.get("venue_id") ?? "");
  if (formData.get("apply_organizer_id") === "on") {
    patch.organizer_id = String(formData.get("organizer_id") ?? "") || null;
  }
  if (formData.get("apply_status") === "on") patch.status = String(formData.get("status") ?? "scheduled");
  if (formData.get("apply_is_free") === "on") patch.is_free = formData.get("is_free") === "on";
  applyNumber("price_min");
  applyNumber("price_max");
  applyText("ticket_url");
  applyText("doors_info");
  applyText("age_restriction");
  applyText("discount_info");
  applyText("presale_fee_info");
  if (formData.get("apply_remaining_tickets_status") === "on") {
    patch.remaining_tickets_status = String(formData.get("remaining_tickets_status") ?? "") || null;
  }

  const applyGenres = formData.get("apply_genre_ids") === "on";
  const genreIds = formData.getAll("genre_ids").map(String);

  if (Object.keys(patch).length === 0 && !applyGenres) {
    return { updated: 0, error: "Keine Felder zum Übernehmen ausgewählt." };
  }

  if (Object.keys(patch).length > 0) {
    patch.updated_at = new Date().toISOString();
    const { error } = await supabase.from("events").update(patch).in("id", eventIds);
    if (error) return { updated: 0, error: error.message };
  }

  if (applyGenres) {
    await supabase.from("event_genres").delete().in("event_id", eventIds);
    if (genreIds.length > 0) {
      const rows = eventIds.flatMap((event_id) => genreIds.map((genre_id) => ({ event_id, genre_id })));
      const { error } = await supabase.from("event_genres").insert(rows);
      if (error) return { updated: 0, error: error.message };
    }
  }

  revalidatePath("/events");
  return { updated: eventIds.length };
}

export async function deleteEvent(eventId: string) {
  const supabase = await createClient();
  const { data: existing } = await supabase.from("events").select("program_id").eq("id", eventId).maybeSingle();

  const { error } = await supabase.from("events").delete().eq("id", eventId);
  if (error) throw new Error(error.message);

  // War dieses Event das letzte Mitglied einer Event-Gruppe, bliebe die
  // Gruppe sonst leer stehen (Nutzer-Meldung "0 Termine"), siehe
  // event-group-cleanup.ts.
  await cleanupEventGroupIfEmpty(supabase, existing?.program_id ?? null);

  revalidatePath("/events");
  redirect("/events");
}
