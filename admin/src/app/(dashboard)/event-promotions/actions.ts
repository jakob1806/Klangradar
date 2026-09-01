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
    .select("id, status, event_id, requested_by, events(title, start_datetime)")
    .eq("id", id)
    .maybeSingle();
  const promotion = promotionData as unknown as {
    id: string;
    status: string;
    event_id: string;
    requested_by: string;
    events: { title: string; start_datetime: string } | null;
  } | null;
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

  // Postfach-Eintrag im Veranstalterportal (organizer_notifications, siehe
  // 20261201000001) — bei "approved" ist die Promotion technisch erst
  // payment_pending (siehe require_paid_promotion_for_activation-Trigger),
  // die Nachricht macht den nächsten Schritt (Zahlung) deshalb explizit.
  try {
    const eventTitle = promotion.events?.title ?? "dein Event";
    await supabase.from("organizer_notifications").insert({
      user_id: promotion.requested_by,
      type: status === "approved" ? "promotion_approved" : "promotion_rejected",
      title: status === "approved" ? `Promotion für ${eventTitle} freigegeben` : `Promotion für ${eventTitle} abgelehnt`,
      body:
        status === "approved"
          ? "Die Redaktion hat deine Promotion-Anfrage geprüft — schließe jetzt die Zahlung ab, damit sie aktiv wird."
          : reviewerNote.trim() || "Die Redaktion hat deine Promotion-Anfrage abgelehnt.",
      link_href: "/veranstalter/promote",
    });
  } catch (notificationError) {
    console.error("Konnte Postfach-Benachrichtigung nicht anlegen:", notificationError);
  }

  revalidatePath("/event-promotions");
  revalidatePath("/veranstalter/promote");
}
