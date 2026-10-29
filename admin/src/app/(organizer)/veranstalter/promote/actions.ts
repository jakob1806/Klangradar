"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { headers } from "next/headers";
import { createAdminClient } from "@/lib/supabase/admin";
import { activatePaidPromotion, getPlacementPriceLabels, PRICE_ID_BY_PLACEMENT } from "@/lib/promotion-payment";
import { redaktionEmail, sendPortalEmail } from "@/lib/portal-email";
import { promotionApprovedEmail, promotionRequestedEmail, promotionRequestedRedaktionEmail } from "@/lib/notification-emails";
import { getStripe } from "@/lib/stripe";
import { getPromotableEvents } from "./promotable-events";
import { getProStatus } from "@/lib/portal-pro";
import { promotionActiveEmail } from "@/lib/notification-emails";
import { euroToCents, fetchPromotionQuote, promotionWindow, TARGET_AUDIENCES, type PromotionQuote } from "@/lib/promotion-quote";

const AUDIENCES = new Set<string>(TARGET_AUDIENCES.map((audience) => audience.value));

/** Live-Angebot für das Antragsformular (gleiche Rechnung wie beim Antrag). */
export async function quotePromotion(input: {
  eventId: string; placement: string; start: string; end: string; dailyCap: string; totalBudget: string;
}): Promise<{ quote?: PromotionQuote; error?: string }> {
  if (!input.eventId || !PLACEMENTS.has(input.placement)) return {};
  const dailyCap = euroToCents(input.dailyCap);
  const totalBudget = euroToCents(input.totalBudget);
  if (dailyCap === "invalid" || totalBudget === "invalid") return { error: "Bitte Budgets als Betrag in Euro angeben." };
  const supabase = await createClient();
  return fetchPromotionQuote(supabase, {
    eventId: input.eventId, placement: input.placement, start: input.start || null, end: input.end || null,
    dailyCapCents: dailyCap, totalBudgetCents: totalBudget,
  });
}

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

export async function requestPromotion(formData: FormData): Promise<{ error?: string; success?: true; autoApproved?: true }> {
  try {
    const eventId = String(formData.get("event_id") ?? "").trim();
    const placement = String(formData.get("placement") ?? "").trim();
    const note = String(formData.get("requester_note") ?? "").trim();

    if (!eventId || !PLACEMENTS.has(placement)) return { error: "Bitte wähle ein Event und eine Platzierung." };
    if (note.length > 1000) return { error: "Die Nachricht darf höchstens 1.000 Zeichen lang sein." };
    const audiences = formData.getAll("target_audiences").map(String).filter((value) => AUDIENCES.has(value));
    const dailyCap = euroToCents(formData.get("daily_cap"));
    const totalBudget = euroToCents(formData.get("total_budget"));
    if (dailyCap === "invalid" || totalBudget === "invalid") return { error: "Bitte Budgets als Betrag in Euro angeben." };

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

    const { quote, error: quoteError } = await fetchPromotionQuote(supabase, {
      eventId,
      placement,
      start: String(formData.get("run_start") ?? "") || null,
      end: String(formData.get("run_end") ?? "") || null,
      dailyCapCents: dailyCap,
      totalBudgetCents: totalBudget,
    });
    if (!quote) return { error: quoteError ?? "Für diese Laufzeit ist kein Angebot möglich." };
    if (quote.days_included === 0) return { error: "Mit diesem Budget bleibt kein Tag übrig. Bitte Budget erhöhen oder Laufzeit ändern." };

    const { data: inserted, error } = await supabase.from("event_promotions").insert({
      event_id: eventId,
      requested_by: user.id,
      placement,
      requester_note: note || null,
      run_start: quote.first_day,
      run_end: quote.last_day,
      daily_cap_cents: dailyCap,
      total_budget_cents: totalBudget,
      target_audiences: audiences,
      quoted_amount_cents: quote.dynamic ? quote.amount_cents : null,
    }).select("id").single();
    if (error) return { error: `Die Anfrage konnte nicht gespeichert werden: ${error.message}` };

    const event = events.find((item) => item.id === eventId);
    const priceLabels = await getPlacementPriceLabels();
    const info = { eventTitle: event?.title ?? "dein Event", placement, concertAt: event?.startDatetime ?? null, priceLabel: priceLabels[placement] };

    // Portal Pro: Standard-Platzierungen aus dem Monatskontingent sind sofort
    // aktiv, ohne Zahlung.
    if (placement === "standard" && inserted?.id && event?.organizerId) {
      const pro = await getProStatus(event.organizerId);
      if (pro.active && pro.used < pro.limit) {
        const { data: activated } = await createAdminClient()
          .from("event_promotions")
          .update({
            status: "approved",
            payment_status: "included",
            reviewed_at: new Date().toISOString(),
            starts_at: promotionWindow(quote.first_day, quote.last_day, event.startDatetime).startsAt,
            ends_at: promotionWindow(quote.first_day, quote.last_day, event.startDatetime).endsAt,
          })
          .eq("id", inserted.id)
          .eq("status", "pending")
          .select("id");
        if (activated?.length) {
          await sendPortalEmail(user.email, promotionActiveEmail({ eventTitle: info.eventTitle, placement, concertAt: info.concertAt, amountLabel: "im Portal-Pro-Abo enthalten", promotionId: inserted.id }));
          revalidatePath("/veranstalter/promote");
          revalidatePath("/veranstalter/finanzen");
          return { success: true, autoApproved: true };
        }
      }
    }

    // Standard-Platzierung braucht keine redaktionelle Prüfung: sofort
    // zahlbar (Service-Client, Veranstalter dürfen den Status per RLS nicht
    // selbst setzen). Die Redaktion wird nur informiert.
    if (placement === "standard" && inserted?.id && event && !note) {
      const { data: approved } = await createAdminClient()
        .from("event_promotions")
        .update({ status: "payment_pending", reviewed_at: new Date().toISOString() })
        .eq("id", inserted.id)
        .eq("status", "pending")
        .select("id");
      if (approved?.length) {
        await sendPortalEmail(user.email, promotionApprovedEmail({ ...info, reviewerNote: null }));
        revalidatePath("/veranstalter/promote");
        return { success: true, autoApproved: true };
      }
    }

    await Promise.all([
      sendPortalEmail(user.email, promotionRequestedEmail(info)),
      sendPortalEmail(redaktionEmail(), promotionRequestedRedaktionEmail({ ...info, requester: user.email ?? "Ein:e Veranstalter:in" })),
    ]);

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
    .select("id, event_id, placement, status, stripe_checkout_session_id, run_start, run_end, daily_cap_cents, total_budget_cents, events(title, start_datetime)")
    .eq("id", promotionId)
    .maybeSingle();
  const row = promotion as unknown as {
    id: string; event_id: string; placement: string; status: string; stripe_checkout_session_id: string | null;
    run_start: string | null; run_end: string | null; daily_cap_cents: number | null; total_budget_cents: number | null;
    events: { title: string; start_datetime: string } | null;
  } | null;
  if (!row) return { error: "Diese Promotion wurde nicht gefunden oder du hast keinen Zugriff darauf." };
  if (row.status !== "payment_pending") return { error: "Diese Promotion wartet nicht (mehr) auf eine Zahlung." };
  if (!row.events || new Date(row.events.start_datetime).getTime() <= Date.now()) {
    return { error: "Das Event hat bereits begonnen — eine Zahlung ist nicht mehr sinnvoll. Bitte storniere die Anfrage." };
  }
  const price = PRICE_ID_BY_PLACEMENT[row.placement];
  if (!price) return { error: "Für diese Platzierung ist kein Preis hinterlegt. Bitte kontaktiere die Redaktion." };

  // Gestaffelte Preise: Betrag zum Zahlungszeitpunkt neu rechnen (schon
  // vergangene Tage der Laufzeit fallen weg und werden nicht berechnet).
  const { quote } = await fetchPromotionQuote(supabase, {
    eventId: row.event_id, placement: row.placement, start: row.run_start, end: row.run_end,
    dailyCapCents: row.daily_cap_cents, totalBudgetCents: row.total_budget_cents,
  });
  if (quote?.dynamic && quote.days_included === 0) {
    return { error: "Die gewählte Laufzeit ist bereits vorbei. Bitte storniere die Anfrage und buche neu." };
  }
  const lineItem = quote?.dynamic && quote.amount_cents > 0
    ? {
        price_data: {
          currency: "eur",
          unit_amount: quote.amount_cents,
          product_data: {
            name: `Klangradar Promotion · ${row.events.title}`,
            description: quote.unit === "push"
              ? `Push am ${quote.first_day}`
              : `${quote.days_included} ${quote.days_included === 1 ? "Tag" : "Tage"}, ${quote.first_day} bis ${quote.last_day}`,
          },
        },
        quantity: 1,
      }
    : { price, quantity: 1 };

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
      line_items: [lineItem],
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
