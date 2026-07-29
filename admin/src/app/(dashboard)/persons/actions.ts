"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readPersonFields(formData: FormData) {
  return {
    slug: String(formData.get("slug") ?? "").trim(),
    full_name: String(formData.get("full_name") ?? "").trim(),
    roles: formData.getAll("roles").map(String),
    instrument: String(formData.get("instrument") ?? "").trim() || null,
    nationality: String(formData.get("nationality") ?? "").trim() || null,
    birth_date: String(formData.get("birth_date") ?? "") || null,
    death_date: String(formData.get("death_date") ?? "") || null,
    biography_de: String(formData.get("biography_de") ?? "").trim() || null,
    website_url: String(formData.get("website_url") ?? "").trim() || null,
    photo_url: String(formData.get("photo_url") ?? "").trim() || null,
    is_verified: formData.get("is_verified") === "on",
  };
}

export async function createPerson(formData: FormData) {
  const f = readPersonFields(formData);
  const supabase = await createClient();
  const { error } = await supabase.from("persons").insert(f);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
  redirect("/persons");
}

export async function updatePerson(personId: string, formData: FormData) {
  const f = readPersonFields(formData);
  const supabase = await createClient();
  const { error } = await supabase
    .from("persons")
    .update({ ...f, updated_at: new Date().toISOString() })
    .eq("id", personId);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
  redirect("/persons");
}

export async function deletePerson(personId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("persons").delete().eq("id", personId);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
  redirect("/persons");
}

export async function bulkDeletePersons(ids: string[]) {
  const supabase = await createClient();
  const { error } = await supabase.from("persons").delete().in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
}

export async function bulkSetPersonsVerified(ids: string[], verified: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.from("persons").update({ is_verified: verified }).in("id", ids);
  if (error) throw new Error(error.message);

  revalidatePath("/persons");
}
