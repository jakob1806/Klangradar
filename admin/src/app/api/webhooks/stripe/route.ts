import Stripe from "stripe";
import { NextResponse } from "next/server";
import { getStripe } from "@/lib/stripe";
import { activatePaidPromotion } from "@/lib/promotion-payment";

export async function POST(request: Request) {
  const signature = request.headers.get("stripe-signature");
  if (!signature) return NextResponse.json({ error: "Signatur fehlt" }, { status: 400 });

  let event: Stripe.Event;
  try {
    event = getStripe().webhooks.constructEvent(await request.text(), signature, process.env.STRIPE_WEBHOOK_SECRET!);
  } catch {
    return NextResponse.json({ error: "Ungültige Signatur" }, { status: 400 });
  }

  // async_payment_succeeded: verzögerte Zahlarten (z. B. SEPA) melden den
  // Zahlungseingang erst später, nicht schon bei checkout.session.completed.
  if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
    await activatePaidPromotion(event.data.object as Stripe.Checkout.Session);
  }

  return NextResponse.json({ received: true });
}
