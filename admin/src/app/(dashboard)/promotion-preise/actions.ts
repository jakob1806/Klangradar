"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { euroToCents } from "@/lib/promotion-quote";

// Erstellt von Claude Code (29.10.2026): Preisstaffeln für Promotionen
// speichern und gestaffelte Preise ein- oder ausschalten (nur Admins).
export async function savePromotionPricing(formData: FormData) {
  const tiers: { placement: string; min_days_before: number; rate_cents: number }[] = [];
  for (const [key, value] of formData.entries()) {
    const match = /^rate:([a-z_]+):(\d+)$/.exec(key);
    if (!match) continue;
    const cents = String(value).trim() === "0" ? 0 : euroToCents(value);
    if (cents === null) continue;
    if (cents === "invalid") throw new Error(`Ungültiger Preis bei ${match[1]}.`);
    tiers.push({ placement: match[1], min_days_before: Number(match[2]), rate_cents: cents });
  }
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_promotion_pricing", {
    p_dynamic_enabled: formData.get("dynamic_enabled") === "on",
    p_tiers: tiers,
  });
  if (error) throw new Error(error.message);
  revalidatePath("/promotion-preise");
}
