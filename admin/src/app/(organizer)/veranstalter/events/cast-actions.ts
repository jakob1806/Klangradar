"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/components/organizer/action-form";

// Erstellt von Claude Code (29.10.2026): Besetzungsänderung melden. Alle, die
// den Termin gemerkt haben, bekommen daraus eine Push-Mitteilung
// (notify-changes, gleicher Weg wie die automatische Erkennung).
export async function reportCastChange(eventId: string, _state: ActionResult, formData: FormData): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("organizer_report_cast_change", {
    p_event_id: eventId,
    p_removed: String(formData.get("removed") ?? ""),
    p_added: String(formData.get("added") ?? ""),
  });
  if (error) return { error: error.message };
  revalidatePath(`/veranstalter/events/${eventId}`);
  return { success: "Gemeldet. Alle, die den Termin gemerkt haben, bekommen in den nächsten Minuten eine Mitteilung." };
}
