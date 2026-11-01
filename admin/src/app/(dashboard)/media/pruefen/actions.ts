"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (01.11.2026): Entscheidungen der Schnellprüfung.
export interface ReviewDecision {
  kind: "license" | "flag" | "report";
  imageId: string | null;
  flagId: string | null;
  reportId: string | null;
  entityType: string;
  entityId: string;
  imageUrl: string;
  free: boolean;
}

export async function decideImage(item: ReviewDecision, keep: boolean): Promise<void> {
  const supabase = await createClient();
  let error: { message: string } | null = null;
  if (item.kind === "license" && item.imageId) {
    ({ error } = await supabase.rpc("review_images", {
      p_ids: [item.imageId],
      p_status: keep ? (item.free ? "confirmed_free" : "confirmed_licensed") : "rejected",
    }));
  } else if (keep) {
    ({ error } = await supabase.rpc("admin_keep_entity_photo", { p_flag_id: item.flagId, p_report_id: item.reportId }));
  } else {
    ({ error } = await supabase.rpc("admin_remove_entity_photo", {
      p_entity_type: item.entityType, p_entity_id: item.entityId, p_photo_url: item.imageUrl,
    }));
  }
  if (error) throw new Error(error.message);
  revalidatePath("/media/pruefen");
}
