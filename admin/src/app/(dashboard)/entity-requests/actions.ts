"use server";

// Erstellt von Claude Code (26.10.2026): Nutzeranfragen für fehlende
// Personen/Ensembles/Orte/Werke abschließen.
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function setEntityRequestStatus(requestId: string, status: "done" | "rejected") {
  const supabase = await createClient();
  const { error } = await supabase
    .from("entity_requests")
    .update({ status, reviewed_at: new Date().toISOString() })
    .eq("id", requestId);
  if (error) throw new Error(error.message);
  revalidatePath("/entity-requests");
}
