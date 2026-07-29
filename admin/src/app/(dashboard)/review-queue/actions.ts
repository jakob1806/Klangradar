"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

/** review_status ist rein redaktionelle Triage (siehe Datei-Kommentar in
 * page.tsx) — "als geprüft markieren" heißt nur, dass es aus dieser Liste
 * verschwindet, das Event selbst bleibt unverändert live. */
export async function bulkClearReview(eventIds: string[]): Promise<{ updated: number; error?: string }> {
  if (eventIds.length === 0) return { updated: 0 };
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("events")
    .update({ review_status: "published" })
    .in("id", eventIds)
    .select("id");
  if (error) return { updated: 0, error: error.message };

  revalidatePath("/review-queue");
  return { updated: data?.length ?? 0 };
}

/** Anders als "als geprüft markieren": setzt zusätzlich status='draft', das
 * Event verschwindet damit auch aus der öffentlichen App (RLS: "status !=
 * 'draft' or is_admin_or_editor()") — für Events, die sich beim Prüfen als
 * tatsächlich fehlerhaft/nicht veröffentlichbar herausstellen, reversibel
 * über die normale Bearbeiten-Seite. */
export async function bulkRejectReview(eventIds: string[]): Promise<{ updated: number; error?: string }> {
  if (eventIds.length === 0) return { updated: 0 };
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("events")
    .update({ review_status: "rejected", status: "draft", updated_at: new Date().toISOString() })
    .in("id", eventIds)
    .select("id");
  if (error) return { updated: 0, error: error.message };

  revalidatePath("/review-queue");
  return { updated: data?.length ?? 0 };
}
