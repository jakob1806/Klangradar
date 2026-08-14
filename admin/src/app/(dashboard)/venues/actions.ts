"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readVenueFields(formData: FormData) {
  return {
    slug: String(formData.get("slug") ?? "").trim(),
    name: String(formData.get("name") ?? "").trim(),
    description_de: String(formData.get("description_de") ?? "").trim() || null,
    address_street: String(formData.get("address_street") ?? "").trim(),
    address_zip: String(formData.get("address_zip") ?? "").trim(),
    address_city: String(formData.get("address_city") ?? "München").trim(),
    lat: Number(formData.get("lat")),
    lng: Number(formData.get("lng")),
    capacity: formData.get("capacity") ? Number(formData.get("capacity")) : null,
    website_url: String(formData.get("website_url") ?? "").trim() || null,
    photo_url: String(formData.get("photo_url") ?? "").trim() || null,
  };
}

export async function createVenue(formData: FormData) {
  const f = readVenueFields(formData);
  const supabase = await createClient();
  const { data: resolved } = await supabase.rpc("resolve_entity_alias", { p_entity_type: "venue", p_name: f.name });
  if (resolved?.[0]?.id) redirect(`/venues/${resolved[0].id}`);

  const { error } = await supabase.rpc("create_venue", {
    p_slug: f.slug,
    p_name: f.name,
    p_description_de: f.description_de,
    p_address_street: f.address_street,
    p_address_zip: f.address_zip,
    p_address_city: f.address_city,
    p_lat: f.lat,
    p_lng: f.lng,
    p_capacity: f.capacity,
    p_website_url: f.website_url,
    p_photo_url: f.photo_url,
  });

  if (error) throw new Error(error.message);

  revalidatePath("/venues");
  redirect("/venues");
}

export async function updateVenue(venueId: string, formData: FormData) {
  const f = readVenueFields(formData);
  const supabase = await createClient();

  const { error } = await supabase.rpc("update_venue", {
    p_id: venueId,
    p_slug: f.slug,
    p_name: f.name,
    p_description_de: f.description_de,
    p_address_street: f.address_street,
    p_address_zip: f.address_zip,
    p_address_city: f.address_city,
    p_lat: f.lat,
    p_lng: f.lng,
    p_capacity: f.capacity,
    p_website_url: f.website_url,
    p_photo_url: f.photo_url,
  });

  if (error) throw new Error(error.message);

  revalidatePath("/venues");
  redirect("/venues");
}

export interface VenueDeleteInfo {
  events: { id: string; title: string }[];
  ensembles: { id: string; name: string }[];
  sources: { id: string; name: string }[];
  candidateCount: number;
}

// events.venue_id/ensembles.home_venue_id/sources.venue_id/
// entity_candidates.suggested_venue_id haben KEIN ON DELETE CASCADE.
// Gleiches Verhalten wie bei Ensembles/Personen (siehe
// ensembles/actions.ts): erst zeigen, was noch verknüpft ist, dann
// trotzdem löschen dürfen statt zu blockieren.
export async function getVenueDeleteInfo(venueId: string): Promise<VenueDeleteInfo> {
  const supabase = await createClient();
  const [{ data: events }, { data: ensembles }, { data: sources }, { count: candidateCount }] = await Promise.all([
    supabase.from("events").select("id, title").eq("venue_id", venueId).returns<{ id: string; title: string }[]>(),
    supabase.from("ensembles").select("id, name").eq("home_venue_id", venueId).returns<{ id: string; name: string }[]>(),
    supabase.from("sources").select("id, name").eq("venue_id", venueId).returns<{ id: string; name: string }[]>(),
    supabase
      .from("entity_candidates")
      .select("id", { count: "exact", head: true })
      .eq("suggested_venue_id", venueId),
  ]);

  return {
    events: events ?? [],
    ensembles: ensembles ?? [],
    sources: sources ?? [],
    candidateCount: candidateCount ?? 0,
  };
}

/** Löst alle Verweise auf diesen Venue, bevor er gelöscht wird — anders als
 * bei Ensembles/Personen werden Veranstaltungen NICHT gelöscht (ein Event
 * ohne Ort wäre eigenständiger Content-Verlust, keine bloße Zuordnung) —
 * events.venue_id wird nur auf null gesetzt, ensembles.home_venue_id/
 * sources.venue_id/entity_candidates.suggested_venue_id ebenso. */
async function detachVenueReferences(
  supabase: Awaited<ReturnType<typeof createClient>>,
  venueId: string,
) {
  await supabase.from("events").update({ venue_id: null }).eq("venue_id", venueId);
  await supabase.from("ensembles").update({ home_venue_id: null }).eq("home_venue_id", venueId);
  await supabase.from("sources").update({ venue_id: null }).eq("venue_id", venueId);
  await supabase.from("entity_candidates").update({ suggested_venue_id: null }).eq("suggested_venue_id", venueId);
}

export async function deleteVenue(venueId: string) {
  const supabase = await createClient();
  await detachVenueReferences(supabase, venueId);

  const { error } = await supabase.from("venues").delete().eq("id", venueId);
  if (error) throw new Error(error.message);

  revalidatePath("/venues");
  redirect("/venues");
}

export async function bulkDeleteVenues(ids: string[]) {
  const supabase = await createClient();
  for (const id of ids) {
    await detachVenueReferences(supabase, id);
  }

  const { error } = await supabase.from("venues").delete().in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/venues");
}

export async function bulkSetVenuesVerified(ids: string[], verified: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.from("venues").update({ is_verified: verified }).in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/venues");
}
