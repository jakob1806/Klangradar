"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Nutzerwunsch: "bei erneut versuchen soll einfach eine KI diese fehler
// durchgehen und beheben ... als eigene aufgabe an claude code übergeben".
// Die Zeilen selbst legt die Edge Function auto-fix-content-report an
// (siehe code_fix_tasks-Migration) — hier nur das manuelle Abhaken, sobald
// Claude Code die Aufgabe tatsächlich bearbeitet hat.
export async function markCodeFixTaskDone(taskId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("code_fix_tasks")
    .update({ status: "done", resolved_at: new Date().toISOString() })
    .eq("id", taskId);
  if (error) throw new Error(error.message);
  revalidatePath("/code-fix-tasks");
}
