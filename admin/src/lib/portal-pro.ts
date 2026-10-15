import type Stripe from "stripe";
import { getStripe } from "@/lib/stripe";
import { createAdminClient } from "@/lib/supabase/admin";

// Portal Pro (docs/15-preise-und-klangradar-plus.md): Monatsabo für
// Veranstalter mit vielen Terminen. Preis inline als price_data, damit kein
// Stripe-Produkt vorab angelegt werden muss; STRIPE_PRICE_PORTAL_PRO
// überschreibt das, sobald es eins gibt.
export const PRO_MONTHLY_CENTS = 4900;
export const PRO_INCLUDED_STANDARD = 4;
export const PRO_BENEFITS = [
  `${PRO_INCLUDED_STANDARD} Standard-Platzierungen pro Monat inklusive (Einzelpreis je 29 €)`,
  "Sofort aktiv, ohne Einzelzahlung pro Konzert",
  "Monatlich kündbar, Rechnungen direkt von Stripe",
];

const ACTIVE = new Set(["active", "trialing", "past_due"]);

export type ProStatus = {
  active: boolean;
  status: string | null;
  used: number;
  limit: number;
  periodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  customerId: string | null;
};

export async function getProStatus(organizerId: string): Promise<ProStatus> {
  const db = createAdminClient();
  const { data: sub } = await db
    .from("organizer_subscriptions")
    .select("status, current_period_start, current_period_end, cancel_at_period_end, stripe_customer_id")
    .eq("organizer_id", organizerId)
    .maybeSingle();
  const active = Boolean(sub && ACTIVE.has(sub.status as string) && (!sub.current_period_end || new Date(sub.current_period_end as string) > new Date()));
  let used = 0;
  if (active && sub?.current_period_start) {
    const { count } = await db
      .from("event_promotions")
      .select("id, events!inner(organizer_id)", { count: "exact", head: true })
      .eq("events.organizer_id", organizerId)
      .eq("payment_status", "included")
      .gte("requested_at", sub.current_period_start as string);
    used = count ?? 0;
  }
  return {
    active,
    status: (sub?.status as string) ?? null,
    used,
    limit: PRO_INCLUDED_STANDARD,
    periodEnd: (sub?.current_period_end as string) ?? null,
    cancelAtPeriodEnd: Boolean(sub?.cancel_at_period_end),
    customerId: (sub?.stripe_customer_id as string) ?? null,
  };
}

export async function createProCheckoutSession(input: { organizerId: string; organizerName: string; email: string | null | undefined; origin: string; customerId?: string | null }): Promise<string | null> {
  const priceId = process.env.STRIPE_PRICE_PORTAL_PRO;
  const session = await getStripe().checkout.sessions.create({
    mode: "subscription",
    line_items: [
      priceId
        ? { price: priceId, quantity: 1 }
        : {
            quantity: 1,
            price_data: {
              currency: "eur",
              unit_amount: PRO_MONTHLY_CENTS,
              recurring: { interval: "month" },
              product_data: { name: "Klangradar Portal Pro", description: PRO_BENEFITS.join(" · ") },
            },
          },
    ],
    customer: input.customerId ?? undefined,
    customer_email: input.customerId ? undefined : (input.email ?? undefined),
    metadata: { organizer_id: input.organizerId, kind: "portal_pro" },
    subscription_data: { metadata: { organizer_id: input.organizerId, kind: "portal_pro" }, description: `Portal Pro · ${input.organizerName}` },
    allow_promotion_codes: true,
    billing_address_collection: "required",
    tax_id_collection: { enabled: true },
    locale: "de",
    success_url: `${input.origin}/veranstalter/finanzen?pro=success`,
    cancel_url: `${input.origin}/veranstalter/finanzen?pro=cancelled`,
  });
  return session.url;
}

export async function createProPortalSession(customerId: string, origin: string): Promise<string> {
  const session = await getStripe().billingPortal.sessions.create({ customer: customerId, return_url: `${origin}/veranstalter/finanzen`, locale: "de" });
  return session.url;
}

/** Spiegelt ein Stripe-Abo nach organizer_subscriptions (Webhook, idempotent). */
export async function syncProSubscription(subscription: Stripe.Subscription): Promise<void> {
  const organizerId = subscription.metadata?.organizer_id;
  if (!organizerId || subscription.metadata?.kind !== "portal_pro") return;
  const item = subscription.items?.data?.[0];
  const toIso = (seconds: number | null | undefined) => (seconds ? new Date(seconds * 1000).toISOString() : null);
  await createAdminClient()
    .from("organizer_subscriptions")
    .upsert({
      organizer_id: organizerId,
      plan: "pro",
      status: subscription.status,
      stripe_customer_id: typeof subscription.customer === "string" ? subscription.customer : subscription.customer?.id ?? null,
      stripe_subscription_id: subscription.id,
      current_period_start: toIso(item?.current_period_start),
      current_period_end: toIso(item?.current_period_end),
      cancel_at_period_end: subscription.cancel_at_period_end,
      updated_at: new Date().toISOString(),
    });
}

/** Nach checkout.session.completed (mode=subscription). */
export async function syncProFromCheckout(session: Stripe.Checkout.Session): Promise<void> {
  if (session.mode !== "subscription" || session.metadata?.kind !== "portal_pro" || !session.subscription) return;
  const id = typeof session.subscription === "string" ? session.subscription : session.subscription.id;
  await syncProSubscription(await getStripe().subscriptions.retrieve(id));
}
