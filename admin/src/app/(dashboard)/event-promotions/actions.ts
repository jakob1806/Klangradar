"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logSystemAction } from "@/lib/system-log";

const STATUSES = new Set(["approved", "rejected"]);

export async function reviewPromotion(id: string, status: "approved" | "rejected", reviewerNote: string) {
  if (!STATUSES.has(status)) throw new Error("Ungültige Entscheidung.");
  if (reviewerNote.trim().length > 1000) throw new Error("Die redaktionelle Notiz darf höchstens 1.000 Zeichen lang sein.");

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Nicht angemeldet.");

  // Eine Freigabe läuft vom aktuellen Zeitpunkt bis zum Eventbeginn. Die
  // konsumierenden Clients können damit einfach approved + Zeitfenster lesen;
  // ein späteres Buchungs-/Abrechnungssystem muss keinen Status umbiegen.
  const { data: promotionData, error: loadError } = await supabase
    .from("event_promotions")
    .select("id, status, event_id, events(start_datetime)")
    .eq("id", id)
    .maybeSingle();
  const promotion = promotionData as unknown as { id: string; status: string; event_id: string; events: { start_datetime: string } | null } | null;
  if (loadError || !promotion) throw new Error(loadError?.message ?? "Promotion nicht gefunden.");
  if (promotion.status !== "pending") throw new Error("Diese Promotion wurde bereits entschieden.");

  const event = promotion.events;
  if (status === "approved" && (!event || new Date(event.start_datetime).getTime() <= Date.now())) {
    throw new Error("Abgelaufene Events können nicht freigegeben werden.");
  }

  const reviewedAt = new Date().toISOString();
  const { error } = await supabase
    .from("event_promotions")
    .update({
      status: status === "approved" ? "payment_pending" : "rejected",
      reviewer_note: reviewerNote.trim() || null,
      reviewed_by: user.id,
      reviewed_at: reviewedAt,
      ...(status === "approved" ? {} : {}),
    })
    .eq("id", id)
    .eq("status", "pending");
  if (error) throw new Error(error.message);

  await logSystemAction(supabase, { entityType: "event_promotion", entityId: id, action: status, actor: user.email ?? user.id });
  revalidatePath("/event-promotions");
  revalidatePath("/veranstalter/promote");
}
