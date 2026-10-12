"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { headers } from "next/headers";
import { createAdminClient } from "@/lib/supabase/admin";
import { activatePaidPromotion, PRICE_ID_BY_PLACEMENT } from "@/lib/promotion-payment";
import { getStripe } from "@/lib/stripe";
import { getPromotableEvents } from "./promotable-events";

export async function cancelPromotion(promotionId: string): Promise<{ error?: string }> {
  const supabase = await createClient();
  const { data: before } = await supabase.from("event_promotions").select("stripe_checkout_session_id").eq("id", promotionId).maybeSingle();
  const { error } = await supabase.rpc("cancel_promotion", { p_promotion_id: promotionId });
  if (error) return { error: error.message };
  // Offenen Checkout ungültig machen, damit nach dem Stornieren nicht doch
  // noch bezahlt werden kann (der Webhook würde die Zahlung ignorieren).
  const sessionId = before?.stripe_checkout_session_id as string | null | undefined;
  if (sessionId) {
    try {
      const stripe = getStripe();
      const session = await stripe.checkout.sessions.retrieve(sessionId);
      if (session.status === "open") await stripe.checkout.sessions.expire(sessionId);
    } catch (cause) {
      console.error("Could not expire checkout session", cause);
    }
  }
  revalidatePath("/veranstalter/promote");
  revalidatePath("/veranstalter/finanzen");
  return {};
}

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

/**
 * Öffnet den Stripe-Checkout für eine freigegebene Promotion. Gibt eine URL
 * oder eine verständliche Fehlermeldung zurück (vorher: Exception → Next-
 * Fehlerseite). Eine noch offene Checkout-Session wird wiederverwendet, damit
 * mehrfaches Klicken nicht zu mehreren bezahlbaren Sessions führt.
 */
export async function createPromotionCheckout(promotionId: string): Promise<{ url?: string; error?: string }> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Bitte melde dich erneut an." };

  // RLS: sichtbar für Antragsteller:in und Team-Mitglieder mit Marketing-/Finanzrolle.
  const { data: promotion } = await supabase
    .from("event_promotions")
    .select("id, placement, status, stripe_checkout_session_id, events(title, start_datetime)")
    .eq("id", promotionId)
    .maybeSingle();
  const row = promotion as unknown as {
    id: string; placement: string; status: string; stripe_checkout_session_id: string | null;
    events: { title: string; start_datetime: string } | null;
  } | null;
  if (!row) return { error: "Diese Promotion wurde nicht gefunden oder du hast keinen Zugriff darauf." };
  if (row.status !== "payment_pending") return { error: "Diese Promotion wartet nicht (mehr) auf eine Zahlung." };
  if (!row.events || new Date(row.events.start_datetime).getTime() <= Date.now()) {
    return { error: "Das Event hat bereits begonnen — eine Zahlung ist nicht mehr sinnvoll. Bitte storniere die Anfrage." };
  }
  const price = PRICE_ID_BY_PLACEMENT[row.placement];
  if (!price) return { error: "Für diese Platzierung ist kein Preis hinterlegt. Bitte kontaktiere die Redaktion." };

  try {
    const stripe = getStripe();
    if (row.stripe_checkout_session_id) {
      const existing = await stripe.checkout.sessions.retrieve(row.stripe_checkout_session_id);
      if (existing.payment_status === "paid") {
        await activatePaidPromotion(existing);
        revalidatePath("/veranstalter/promote");
        return { error: "Diese Promotion ist bereits bezahlt und jetzt aktiv." };
      }
      if (existing.status === "open" && existing.url) return { url: existing.url };
    }

    const headerList = await headers();
    const host = headerList.get("x-forwarded-host") ?? headerList.get("host");
    const proto = headerList.get("x-forwarded-proto") ?? "https";
    const origin = host ? `${proto}://${host}` : (process.env.NEXT_PUBLIC_APP_URL ?? "https://klangradar.com");

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{ price, quantity: 1 }],
      metadata: { promotion_id: row.id },
      client_reference_id: row.id,
      customer_email: user.email ?? undefined,
      success_url: `${origin}/veranstalter/promote?payment=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${origin}/veranstalter/promote?payment=cancelled`,
    });
    if (!session.url) return { error: "Der Checkout konnte nicht erstellt werden. Bitte versuche es erneut." };

    // Service-Client: Veranstalter dürfen Zahlungsfelder per RLS nicht selbst setzen.
    await createAdminClient().from("event_promotions").update({ stripe_checkout_session_id: session.id }).eq("id", row.id).eq("status", "payment_pending");
    return { url: session.url };
  } catch (cause) {
    console.error("Checkout creation failed", cause);
    return { error: "Die Zahlungsseite konnte gerade nicht geöffnet werden. Bitte versuche es gleich noch einmal." };
  }
}
