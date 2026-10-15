import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { getStripe } from "@/lib/stripe";
import { accountEmail, redaktionEmail, sendPortalEmail } from "@/lib/portal-email";
import {
  claimReviewReminderRedaktionEmail,
  promotionExpiredEmail,
  promotionPaymentReminderEmail,
  promotionReviewReminderRedaktionEmail,
  promotionSummaryEmail,
} from "@/lib/notification-emails";
import { getPlacementPriceLabels } from "@/lib/promotion-payment";
import { loadPromotionStats } from "@/lib/promotion-stats";
import { resolveEntityNames, type ClaimableEntityType } from "@/lib/entity-tables";
import { dataQualityEmail, type DataQualityReport } from "@/lib/data-quality-email";

// Täglicher Job (vercel.json → crons). Vercel schickt automatisch
// "Authorization: Bearer $CRON_SECRET", sobald CRON_SECRET gesetzt ist.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

type PromotionRow = {
  id: string;
  placement: string;
  status: string;
  requested_by: string;
  requested_at: string;
  reviewed_at: string | null;
  stripe_checkout_session_id: string | null;
  events: { title: string; start_datetime: string } | null;
};

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET fehlt" }, { status: 500 });
  if (request.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "Nicht autorisiert" }, { status: 401 });

  const db = createAdminClient();
  const now = new Date();
  const threeDaysAgo = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000).toISOString();
  const priceLabels = await getPlacementPriceLabels();
  const result = { paymentReminders: 0, expired: 0, reviewReminders: 0, claimReminders: 0, summaries: 0, qualityReport: false };
  const fields = "id, placement, status, requested_by, requested_at, reviewed_at, stripe_checkout_session_id, events(title, start_datetime)";
  const info = (p: PromotionRow) => ({ eventTitle: p.events?.title ?? "dein Event", placement: p.placement, concertAt: p.events?.start_datetime ?? null, priceLabel: priceLabels[p.placement] });

  // 1) Freigegeben, aber unbezahlt: nach Konzertbeginn verfallen lassen,
  //    sonst nach 3 Tagen einmal erinnern.
  const { data: unpaid } = await db.from("event_promotions").select(`${fields}, payment_reminder_sent_at`).eq("status", "payment_pending").returns<(PromotionRow & { payment_reminder_sent_at: string | null })[]>();
  for (const promotion of unpaid ?? []) {
    const started = !promotion.events || new Date(promotion.events.start_datetime) <= now;
    if (started) {
      const { data: updated } = await db.from("event_promotions").update({ status: "cancelled" }).eq("id", promotion.id).eq("status", "payment_pending").select("id");
      if (!updated?.length) continue;
      if (promotion.stripe_checkout_session_id) {
        try {
          const session = await getStripe().checkout.sessions.retrieve(promotion.stripe_checkout_session_id);
          if (session.status === "open") await getStripe().checkout.sessions.expire(session.id);
        } catch (error) {
          console.error("Checkout-Session konnte nicht beendet werden", error);
        }
      }
      await sendPortalEmail(await accountEmail(promotion.requested_by), promotionExpiredEmail(info(promotion)));
      result.expired++;
    } else if (!promotion.payment_reminder_sent_at && promotion.reviewed_at && promotion.reviewed_at < threeDaysAgo) {
      await sendPortalEmail(await accountEmail(promotion.requested_by), promotionPaymentReminderEmail(info(promotion)));
      await db.from("event_promotions").update({ payment_reminder_sent_at: now.toISOString() }).eq("id", promotion.id);
      result.paymentReminders++;
    }
  }

  // 2) Redaktion: seit über 3 Tagen ungeprüfte Promotion-Anfragen (Sammelmail).
  const { data: pending } = await db.from("event_promotions").select(fields).eq("status", "pending").lt("requested_at", threeDaysAgo).is("review_reminder_sent_at", null).returns<PromotionRow[]>();
  if (pending?.length) {
    await sendPortalEmail(redaktionEmail(), promotionReviewReminderRedaktionEmail(pending.map((p) => ({ eventTitle: p.events?.title ?? "Event", placement: p.placement, requestedAt: p.requested_at }))));
    await db.from("event_promotions").update({ review_reminder_sent_at: now.toISOString() }).in("id", pending.map((p) => p.id));
    result.reviewReminders = pending.length;
  }

  // 3) Redaktion: seit über 3 Tagen offene Claims (Sammelmail).
  const { data: claims } = await db.from("entity_claims").select("id, entity_type, entity_id, created_at").eq("status", "pending").lt("created_at", threeDaysAgo).is("review_reminder_sent_at", null);
  if (claims?.length) {
    const names = await resolveEntityNames(db, claims.map((c) => ({ entityType: c.entity_type as ClaimableEntityType, entityId: c.entity_id as string })));
    await sendPortalEmail(redaktionEmail(), claimReviewReminderRedaktionEmail(claims.map((c) => ({ entityName: names.get(`${c.entity_type}:${c.entity_id}`) ?? "Profil", entityType: c.entity_type as string, createdAt: c.created_at as string }))));
    await db.from("entity_claims").update({ review_reminder_sent_at: now.toISOString() }).in("id", claims.map((c) => c.id));
    result.claimReminders = claims.length;
  }

  // 4) Nach dem Konzerttag: Ergebnis-Mail mit Wirkungsstatistik.
  const { data: finished } = await db.from("event_promotions").select(fields).eq("status", "approved").eq("payment_status", "paid").lt("ends_at", now.toISOString()).is("summary_sent_at", null).returns<PromotionRow[]>();
  for (const promotion of finished ?? []) {
    const stats = await loadPromotionStats(db, promotion.id);
    if (stats) await sendPortalEmail(await accountEmail(promotion.requested_by), promotionSummaryEmail({ ...info(promotion), stats }));
    await db.from("event_promotions").update({ summary_sent_at: now.toISOString() }).eq("id", promotion.id);
    result.summaries++;
  }

  // 5) Täglicher Datenqualitäts-Bericht an die Redaktion.
  const { data: report } = await db.rpc("data_quality_report");
  if (report) {
    await sendPortalEmail(redaktionEmail(), dataQualityEmail(report as DataQualityReport));
    result.qualityReport = true;
  }

  return NextResponse.json(result);
}
