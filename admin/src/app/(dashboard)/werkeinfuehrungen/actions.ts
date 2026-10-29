"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (29.10.2026): von Veranstaltern eingereichte
// Werkeinführungen übernehmen oder ablehnen.
export async function reviewIntroSubmission(id: string, accept: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_review_work_intro_submission", { p_submission_id: id, p_accept: accept });
  if (error) throw new Error(error.message);
  revalidatePath("/werkeinfuehrungen");
}
