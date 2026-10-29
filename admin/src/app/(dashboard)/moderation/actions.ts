"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (29.10.2026): Moderation der Freunde-Funktionen.

export async function resolveUserReport(reportId: number, resolution: "dismissed" | "made_private") {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_resolve_user_report", { p_report_id: reportId, p_resolution: resolution });
  if (error) throw new Error(error.message);
  revalidatePath("/moderation");
}

export async function withdrawFriendRequests(userId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_withdraw_friend_requests", { p_user_id: userId });
  if (error) throw new Error(error.message);
  revalidatePath("/moderation");
}
