"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/components/organizer/action-form";

// Erstellt von Claude Code (29.10.2026): eigene Abos pflegen. Die
// Berechtigung prüfen die Datenbankfunktionen (nur Abos mit eigenen Terminen).

export async function updateOwnSubscription(id: string, _state: ActionResult, formData: FormData): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("organizer_update_subscription", {
    p_subscription_id: id,
    p_name: String(formData.get("name") ?? ""),
    p_url: String(formData.get("url") ?? ""),
  });
  if (error) return { error: error.message };
  revalidatePath("/veranstalter/abos");
  return { success: "Gespeichert. Die App zeigt die Änderung sofort." };
}

export async function setSubscriptionEvent(id: string, eventId: string, linked: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("organizer_set_subscription_event", {
    p_subscription_id: id,
    p_event_id: eventId,
    p_linked: linked,
  });
  if (error) throw new Error(error.message);
  revalidatePath("/veranstalter/abos");
}

export async function addSubscriptionEvent(id: string, _state: ActionResult, formData: FormData): Promise<ActionResult> {
  const eventId = String(formData.get("event_id") ?? "");
  if (!eventId) return { error: "Bitte einen Termin wählen." };
  try {
    await setSubscriptionEvent(id, eventId, true);
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Konnte Termin nicht zuordnen." };
  }
  return { success: "Termin hinzugefügt." };
}
