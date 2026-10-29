"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/components/organizer/action-form";

// Erstellt von Claude Code (29.10.2026): Werkeinführung einreichen; die
// Redaktion prüft und übernimmt sie unter /werkeinfuehrungen.
export async function submitWorkIntroduction(workId: string, _state: ActionResult, formData: FormData): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("organizer_submit_work_introduction", {
    p_work_id: workId,
    p_text: String(formData.get("text") ?? ""),
    p_source_url: String(formData.get("source_url") ?? ""),
  });
  if (error) return { error: error.message };
  revalidatePath("/veranstalter/werkeinfuehrungen");
  return { success: "Eingereicht. Die Redaktion prüft den Text, danach erscheint er in der App." };
}
