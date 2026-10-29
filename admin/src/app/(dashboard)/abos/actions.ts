"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (29.10.2026): Abo-Verwaltung. Bearbeitete Abos
// sind danach "locked" — der automatische Abgleich überschreibt sie nicht.

export async function updateSubscription(id: string, formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_subscription", {
    p_subscription_id: id,
    p_name: String(formData.get("name") ?? ""),
    p_url: String(formData.get("url") ?? ""),
    p_image_url: String(formData.get("image_url") ?? ""),
    p_hidden: formData.get("hidden") === "on",
  });
  if (error) throw new Error(error.message);
  revalidatePath("/abos");
}

export async function mergeSubscription(id: string, formData: FormData) {
  const target = String(formData.get("target") ?? "");
  if (!target) throw new Error("Bitte ein Ziel-Abo wählen.");
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_merge_subscriptions", { p_source: id, p_target: target });
  if (error) throw new Error(error.message);
  revalidatePath("/abos");
}
