"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

/** Saalplan einer Spielstätte setzen oder entfernen (07.11.2026). */
export async function setSeatingPlan(venueId: string, url: string | null) {
  const clean = url?.trim() || null;
  if (clean && !/^https:\/\//i.test(clean)) return { error: "Bitte eine https-Adresse angeben." };
  const supabase = await createClient();
  const { error } = await supabase.from("venues").update({ seating_plan_url: clean }).eq("id", venueId);
  if (error) return { error: error.message };
  revalidatePath(`/venues/${venueId}`);
  revalidatePath("/saalplaene");
  return { error: null };
}
