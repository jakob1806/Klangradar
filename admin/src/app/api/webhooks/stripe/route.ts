import Stripe from "stripe";
import { NextResponse } from "next/server";
import { getStripe } from "@/lib/stripe";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: Request) {
  const signature = request.headers.get("stripe-signature");
  if (!signature) return NextResponse.json({ error: "Signatur fehlt" }, { status: 400 });

  let event: Stripe.Event;
  try {
    event = getStripe().webhooks.constructEvent(await request.text(), signature, process.env.STRIPE_WEBHOOK_SECRET!);
  } catch {
    return NextResponse.json({ error: "Ungültige Signatur" }, { status: 400 });
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session;
    const promotionId = session.metadata?.promotion_id;

    if (promotionId && session.payment_status === "paid") {
      const db = createAdminClient();
      const { data: promotion } = await db
        .from("event_promotions")
        .select("events(start_datetime)")
        .eq("id", promotionId)
        .maybeSingle();
      const eventRow = promotion?.events as unknown as { start_datetime: string } | null;

      // Die Beträge kommen ausschließlich aus der abgeschlossenen Stripe-Session.
      // Das verhindert, dass ein später geänderter Produktpreis alte Zahlungen verfälscht.
      await db
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
        .eq("status", "payment_pending");
    }
  }

  return NextResponse.json({ received: true });
}
