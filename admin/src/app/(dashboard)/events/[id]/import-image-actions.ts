"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

/** Importbild (events.image_urls) entfernen, damit das Galeriebild greift. */
export async function removeImportImage(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  if (!id) return;
  const supabase = await createClient();
  await supabase.from("events").update({ image_urls: [] }).eq("id", id);
  revalidatePath(`/events/${id}`);
  revalidatePath("/events");
}
