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

export async function deleteVenue(venueId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("venues").delete().eq("id", venueId);
  if (error) throw new Error(error.message);

  revalidatePath("/venues");
  redirect("/venues");
}

export async function bulkDeleteVenues(ids: string[]) {
  const supabase = await createClient();
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
