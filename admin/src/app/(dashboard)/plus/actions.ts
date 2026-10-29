"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { munichLocalToISOString } from "@/lib/munich-time";

// Erstellt von Claude Code (29.10.2026): Plus-Codes anlegen (nur Admins).
export async function createPlusCode(formData: FormData) {
  const validUntil = String(formData.get("valid_until") ?? "");
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_create_plus_code", {
    p_code: String(formData.get("code") ?? ""),
    p_duration_days: Number(formData.get("duration_days") || 0),
    p_max_uses: Number(formData.get("max_uses") || 1),
    p_valid_until: validUntil ? munichLocalToISOString(`${validUntil}T23:59`) : null,
    p_note: String(formData.get("note") ?? ""),
    p_allowed_email: String(formData.get("allowed_email") ?? ""),
  });
  if (error) throw new Error(error.message);
  revalidatePath("/plus");
}
