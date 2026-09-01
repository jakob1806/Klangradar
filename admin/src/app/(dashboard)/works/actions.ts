"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function readWork(formData: FormData) {
  const number = (name: string) => {
    const value = String(formData.get(name) ?? "").trim();
    return value ? Number(value) : null;
  };
  return {
    title: String(formData.get("title") ?? "").trim(),
    composer_id: String(formData.get("composer_id") ?? "") || null,
    catalog_number: String(formData.get("catalog_number") ?? "").trim() || null,
    key_signature: String(formData.get("key_signature") ?? "").trim() || null,
    composition_year: number("composition_year"),
    duration_minutes: number("duration_minutes"),
    genre: String(formData.get("genre") ?? "").trim() || null,
    instrumentation: String(formData.get("instrumentation") ?? "").trim() || null,
    description_de: String(formData.get("description_de") ?? "").trim() || null,
  };
}

export async function createWork(formData: FormData) {
  const supabase = await createClient();
  const { data, error } = await supabase.from("works").insert(readWork(formData)).select("id").single<{ id: string }>();
  if (error) throw new Error(error.message);
  revalidatePath("/works");
  redirect(`/works/${data.id}`);
}

export async function updateWork(id: string, formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("works").update(readWork(formData)).eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/works");
  revalidatePath(`/works/${id}`);
}
