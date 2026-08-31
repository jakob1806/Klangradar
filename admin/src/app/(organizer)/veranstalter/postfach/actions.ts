"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function markNotificationRead(id: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("organizer_notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", id)
    .is("read_at", null);
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/postfach");
  revalidatePath("/veranstalter");
}

// Für den "Zur Meldung"-Klick in der Liste: als gelesen markieren und in
// einem Aufwasch zum verknüpften Portal-Bereich weiterleiten — spart eine
// eigene Client-Komponente nur für "erst POST, dann navigieren".
export async function markNotificationReadAndGo(id: string, href: string) {
  const supabase = await createClient();
  await supabase.from("organizer_notifications").update({ read_at: new Date().toISOString() }).eq("id", id).is("read_at", null);
  revalidatePath("/veranstalter/postfach");
  redirect(href || "/veranstalter");
}

export async function markAllNotificationsRead() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet.");

  const { error } = await supabase
    .from("organizer_notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("user_id", user.id)
    .is("read_at", null);
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/postfach");
  revalidatePath("/veranstalter");
}
