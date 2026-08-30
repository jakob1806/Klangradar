"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { getStripe } from "@/lib/stripe";
import { getPromotableEvents } from "./promotable-events";

const PLACEMENTS = new Set(["standard", "featured", "local_spotlight", "homepage_feature", "push"]);

export async function requestPromotion(formData: FormData): Promise<{ error?: string; success?: true }> {
  try {
    const eventId = String(formData.get("event_id") ?? "").trim();
    const placement = String(formData.get("placement") ?? "").trim();
    const note = String(formData.get("requester_note") ?? "").trim();

    if (!eventId || !PLACEMENTS.has(placement)) return { error: "Bitte wähle ein Event und eine Platzierung." };
    if (note.length > 1000) return { error: "Die Nachricht darf höchstens 1.000 Zeichen lang sein." };

    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return { error: "Bitte melde dich erneut an." };

  // RLS ist die verbindliche zweite Schranke. Diese Prüfung liefert der UI
  // aber eine klare Antwort, statt eine rohe Policy-Fehlermeldung zu zeigen.
    const { events, error: accessibleEventsError } = await getPromotableEvents();
    if (accessibleEventsError) return { error: "Deine berechtigten Events konnten gerade nicht geprüft werden. Bitte versuche es erneut." };
    if (!events.some((event) => event.id === eventId)) {
      return { error: "Dieses Event ist nicht mehr kommend, nicht veröffentlicht oder gehört nicht zu einem von dir beanspruchten Profil." };
    }

    const { error } = await supabase.from("event_promotions").insert({
      event_id: eventId,
      requested_by: user.id,
      placement,
      requester_note: note || null,
    });
    if (error) return { error: `Die Anfrage konnte nicht gespeichert werden: ${error.message}` };

    revalidatePath("/veranstalter/promote");
    return { success: true };
  } catch (cause) {
    console.error("Promotion request failed", cause);
    return { error: "Die Anfrage konnte derzeit nicht verarbeitet werden. Bitte versuche es gleich noch einmal." };
  }
}

const PRICE_BY_PLACEMENT: Record<string, string> = { standard: "price_1U9otxCkrdnLOI0hTRLkOdoW", featured: "price_1U9ouVCkrdnLOI0hCbzW8jWj", local_spotlight: "price_1U9oukCkrdnLOI0hBkihCzyF", push: "price_1U9ov5CkrdnLOI0hFUwOpA6i", homepage_feature: "price_1U9ovMCkrdnLOI0hqkPMYDag" };
export async function createPromotionCheckout(promotionId: string) { const supabase = await createClient(); const { data: { user } } = await supabase.auth.getUser(); if (!user) throw new Error("Nicht angemeldet."); const { data: promotion } = await supabase.from("event_promotions").select("id, placement, status, requested_by").eq("id", promotionId).maybeSingle(); if (!promotion || promotion.requested_by !== user.id || promotion.status !== "payment_pending") throw new Error("Diese Promotion kann nicht bezahlt werden."); const price = PRICE_BY_PLACEMENT[promotion.placement as string]; if (!price) throw new Error("Kein Preis hinterlegt."); const origin = process.env.NEXT_PUBLIC_APP_URL ?? "https://klangradar.com"; const session = await getStripe().checkout.sessions.create({ mode: "payment", line_items: [{ price, quantity: 1 }], metadata: { promotion_id: promotionId }, success_url: `${origin}/veranstalter/promote?payment=success`, cancel_url: `${origin}/veranstalter/promote?payment=cancelled` }); if (!session.url) throw new Error("Checkout konnte nicht erstellt werden."); redirect(session.url); }
