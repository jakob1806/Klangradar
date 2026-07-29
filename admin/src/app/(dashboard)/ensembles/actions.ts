"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readEnsembleFields(formData: FormData) {
  return {
    slug: String(formData.get("slug") ?? "").trim(),
    name: String(formData.get("name") ?? "").trim(),
    type: String(formData.get("type") ?? "sonstiges"),
    description_de: String(formData.get("description_de") ?? "").trim() || null,
    founded_year: formData.get("founded_year") ? Number(formData.get("founded_year")) : null,
    member_count: formData.get("member_count") ? Number(formData.get("member_count")) : null,
    home_venue_id: String(formData.get("home_venue_id") ?? "") || null,
    website_url: String(formData.get("website_url") ?? "").trim() || null,
    photo_url: String(formData.get("photo_url") ?? "").trim() || null,
    is_verified: formData.get("is_verified") === "on",
  };
}

export async function createEnsemble(formData: FormData) {
  const f = readEnsembleFields(formData);
  const supabase = await createClient();
  const { error } = await supabase.from("ensembles").insert(f);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
  redirect("/ensembles");
}

export async function updateEnsemble(ensembleId: string, formData: FormData) {
  const f = readEnsembleFields(formData);
  const supabase = await createClient();
  const { error } = await supabase
    .from("ensembles")
    .update({ ...f, updated_at: new Date().toISOString() })
    .eq("id", ensembleId);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
  redirect("/ensembles");
}

export async function deleteEnsemble(ensembleId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("ensembles").delete().eq("id", ensembleId);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
  redirect("/ensembles");
}

export async function bulkDeleteEnsembles(ids: string[]) {
  const supabase = await createClient();
  const { error } = await supabase.from("ensembles").delete().in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
}

export async function bulkSetEnsemblesVerified(ids: string[], verified: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.from("ensembles").update({ is_verified: verified }).in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/ensembles");
}
