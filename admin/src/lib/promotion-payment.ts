import type Stripe from "stripe";
import { getStripe } from "@/lib/stripe";
import { createAdminClient } from "@/lib/supabase/admin";
import { accountEmail, sendPortalEmail } from "@/lib/portal-email";
import { promotionActiveEmail } from "@/lib/notification-emails";

export const PRICE_ID_BY_PLACEMENT: Record<string, string> = {
  standard: "price_1U9otxCkrdnLOI0hTRLkOdoW",
  featured: "price_1U9ouVCkrdnLOI0hCbzW8jWj",
  local_spotlight: "price_1U9oukCkrdnLOI0hBkihCzyF",
  push: "price_1U9ov5CkrdnLOI0hFUwOpA6i",
  homepage_feature: "price_1U9ovMCkrdnLOI0hqkPMYDag",
};

/**
 * Schaltet eine bezahlte Promotion frei. Wird vom Stripe-Webhook UND beim
 * Rücksprung aus dem Checkout aufgerufen — je nachdem, was zuerst ankommt.
 * Idempotent: greift nur, solange die Promotion noch payment_pending ist.
 * Die Beträge kommen ausschließlich aus der abgeschlossenen Stripe-Session.
 */
export async function activatePaidPromotion(session: Stripe.Checkout.Session): Promise<boolean> {
  const promotionId = session.metadata?.promotion_id;
  if (!promotionId || session.payment_status !== "paid") return false;

  const db = createAdminClient();
  const { data: promotion } = await db
    .from("event_promotions")
    .select("placement, requested_by, events(title, start_datetime)")
    .eq("id", promotionId)
    .maybeSingle();
  const eventRow = promotion?.events as unknown as { title: string; start_datetime: string } | null;

  const { data } = await db
    .from("event_promotions")
    .update({
      status: "approved",
      payment_status: "paid",
      stripe_checkout_session_id: session.id,
      payment_amount_cents: session.amount_total,
      payment_currency: session.currency ?? "eur",
      starts_at: new Date().toISOString(),
      ends_at: eventRow?.start_datetime ?? null,
    })
    .eq("id", promotionId)
    .eq("status", "payment_pending")
    .select("id");
  const activated = (data?.length ?? 0) > 0;
  if (activated && promotion) {
    const amountLabel = session.amount_total == null ? null : new Intl.NumberFormat("de-DE", { style: "currency", currency: (session.currency ?? "eur").toUpperCase() }).format(session.amount_total / 100);
    await sendPortalEmail(
      session.customer_details?.email ?? (await accountEmail(promotion.requested_by as string)),
      promotionActiveEmail({ eventTitle: eventRow?.title ?? "dein Event", placement: promotion.placement as string, concertAt: eventRow?.start_datetime ?? null, amountLabel, promotionId }),
    );
  }
  return activated;
}

// Preise ändern sich selten — vorher fragte jede Promote-Seite fünfmal live
// bei Stripe an, das machte die Seite spürbar langsam.
let priceCache: { at: number; labels: Record<string, string> } | null = null;
export async function getPlacementPriceLabels(): Promise<Record<string, string>> {
  if (priceCache && Date.now() - priceCache.at < 60 * 60 * 1000) return priceCache.labels;
  try {
    const entries = await Promise.all(
      Object.entries(PRICE_ID_BY_PLACEMENT).map(async ([placement, priceId]) => {
        const price = await getStripe().prices.retrieve(priceId);
        const label = price.unit_amount == null
          ? null
          : new Intl.NumberFormat("de-DE", { style: "currency", currency: price.currency.toUpperCase() }).format(price.unit_amount / 100);
        return [placement, label] as const;
      }),
    );
    const labels = Object.fromEntries(entries.filter((entry): entry is [string, string] => Boolean(entry[1])));
    priceCache = { at: Date.now(), labels };
    return labels;
  } catch {
    return priceCache?.labels ?? {};
  }
}
