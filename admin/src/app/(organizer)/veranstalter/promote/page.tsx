import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { PromotionRequestForm } from "./promotion-request-form";
import { PromotionCheckoutButton } from "./promotion-checkout-button";
import { PromotionCancelButton } from "./promotion-cancel-button";
import { getPromotableEvents } from "./promotable-events";
import Link from "next/link";
import { getStripe } from "@/lib/stripe";
import { activatePaidPromotion, getPlacementPriceLabels } from "@/lib/promotion-payment";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/organizer/ui/table";

export const dynamic = "force-dynamic";

const PLACEMENT_LABEL: Record<string, string> = { standard: "Standard", featured: "Featured", local_spotlight: "Local Spotlight", homepage_feature: "Homepage Feature", push: "Push-Anfrage" };
const STATUS_LABEL: Record<string, string> = { pending: "In Prüfung", payment_pending: "Zahlung ausstehend", approved: "Freigegeben", rejected: "Abgelehnt", cancelled: "Storniert" };

interface PromotionRow { id: string; placement: string; status: string; payment_status: string | null; payment_amount_cents: number | null; payment_currency: string | null; starts_at: string | null; ends_at: string | null; requester_note: string | null; reviewer_note: string | null; requested_at: string; events: { title: string; start_datetime: string } | null; }

function statusVariant(status: string): "success" | "warning" | "danger" | "default" {
  if (status === "approved") return "success";
  if (status === "payment_pending") return "warning";
  if (status === "rejected" || status === "cancelled") return "danger";
  return "default";
}

function formatCents(cents: number, currency: string | null) {
  return new Intl.NumberFormat("de-DE", { style: "currency", currency: (currency ?? "eur").toUpperCase() }).format(cents / 100);
}

/** Rücksprung aus dem Stripe-Checkout: Zahlung direkt bei Stripe prüfen und
 * freischalten, statt auf den Webhook zu warten. Vorher stand nach dem
 * Bezahlen oft noch "Zahlung ausstehend" samt "Jetzt bezahlen"-Button da. */
async function confirmReturnedCheckout(sessionId: string): Promise<"active" | "processing" | null> {
  try {
    const session = await getStripe().checkout.sessions.retrieve(sessionId);
    const promotionId = session.metadata?.promotion_id;
    if (!promotionId) return null;
    // Nur bestätigen, wenn die Promotion für diese:n Nutzer:in sichtbar ist (RLS).
    const supabase = await createClient();
    const { data } = await supabase.from("event_promotions").select("id").eq("id", promotionId).maybeSingle();
    if (!data) return null;
    if (session.payment_status === "paid") {
      await activatePaidPromotion(session);
      return "active";
    }
    return "processing";
  } catch {
    return null;
  }
}

export default async function PromotePage({ searchParams }: { searchParams: Promise<{ payment?: string; session_id?: string }> }) {
  const { payment, session_id: sessionId } = await searchParams;
  const returnState = payment === "success" && sessionId ? await confirmReturnedCheckout(sessionId) : null;
  const supabase = await createClient();
  const [{ events, error: eventError }, { data: promotionData }, priceLabels] = await Promise.all([
    getPromotableEvents(),
    supabase.from("event_promotions").select("id, placement, status, payment_status, payment_amount_cents, payment_currency, starts_at, ends_at, requester_note, reviewer_note, requested_at, events(title, start_datetime)").order("requested_at", { ascending: false }).returns<PromotionRow[]>(),
    getPlacementPriceLabels(),
  ]);
  const promotions = promotionData ?? [];

  return (
    <div>
      <PageHeader
        eyebrow="Sichtbarkeit"
        title="Push & Promote"
        description="Wähle ein kommendes Event aus deinen eigenen Terminen oder den Terminen beanspruchter Profile. Nach redaktioneller Freigabe erhältst du den Zahlungslink; die Platzierung startet erst nach erfolgreicher Zahlung."
      />
      <PageBody className="flex flex-col gap-10">
        {payment === "success" && (
          <div className="rounded-2xl border border-[#2f6b3a]/20 bg-[#eef7ef] px-5 py-4 text-sm text-[#1f4d28]">
            {returnState === "active"
              ? "Danke, die Zahlung ist eingegangen. Deine Promotion ist jetzt aktiv. Die Rechnung findest du unten und unter Finanzen."
              : "Danke! Die Zahlung wird gerade von Stripe bestätigt. Das dauert meist nur Sekunden – lade die Seite gleich neu."}
          </div>
        )}
        {payment === "cancelled" && (
          <div className="rounded-2xl border border-[#8a5a0c]/20 bg-[#fdf6e9] px-5 py-4 text-sm text-[#6b4508]">
            Die Zahlung wurde abgebrochen, es wurde nichts belastet. Du kannst sie unten jederzeit erneut starten.
          </div>
        )}
        <Card>
          <CardHeader>
            <CardTitle>Neue Promotion</CardTitle>
          </CardHeader>
          <CardContent>
            {eventError ? (
              <p className="text-sm text-[#8a5a0c]">Deine Events konnten gerade nicht geladen werden. Bitte lade die Seite erneut; die Events selbst sind nicht verloren. ({eventError})</p>
            ) : (
              <PromotionRequestForm events={events.map((event) => ({ ...event, startLabel: formatMunichDateTime(event.startDatetime) }))} priceLabels={priceLabels} />
            )}
          </CardContent>
        </Card>
        <section className="flex flex-col gap-3">
          <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">Meine Anfragen</h2>
          {promotions.length === 0 ? (
            <Card>
              <CardContent className="pt-5 text-sm text-[#6B6B6B]">Noch keine Promotionen beantragt.</CardContent>
            </Card>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Event</TableHead>
                  <TableHead>Platzierung</TableHead>
                  <TableHead>Preis</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Hinweis</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {promotions.map((promotion) => (
                  <TableRow key={promotion.id}>
                    <TableCell className="font-medium text-[#111111]">
                      <span className="block">{promotion.events?.title ?? "Gelöschtes Event"}</span>
                      <span className="text-xs font-normal text-[#6B6B6B]">{promotion.events && formatMunichDateTime(promotion.events.start_datetime)}</span>
                    </TableCell>
                    <TableCell className="text-[#4A4A4A]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</TableCell>
                    <TableCell className="whitespace-nowrap tabular-nums text-[#4A4A4A]">
                      {promotion.payment_status === "paid" && promotion.payment_amount_cents != null
                        ? formatCents(promotion.payment_amount_cents, promotion.payment_currency)
                        : priceLabels[promotion.placement] ?? "—"}
                    </TableCell>
                    <TableCell>
                      <Badge variant={statusVariant(promotion.status)}>{STATUS_LABEL[promotion.status] ?? promotion.status}</Badge>
                      {promotion.status === "payment_pending" && (
                        <div className="mt-2">
                          <PromotionCheckoutButton promotionId={promotion.id} priceLabel={priceLabels[promotion.placement]} />
                        </div>
                      )}
                      {promotion.status === "approved" && promotion.ends_at && (
                        <p className="mt-2 text-xs text-[#6B6B6B]">
                          Aktiv bis {formatMunichDateTime(promotion.ends_at)}
                        </p>
                      )}
                      {promotion.payment_status === "paid" && (
                        <Link href={`/veranstalter/finanzen/rechnung/${promotion.id}`} target="_blank" className="mt-1 block text-xs font-medium text-[#2D2A6E] underline">
                          Rechnung (PDF)
                        </Link>
                      )}
                      {(promotion.status === "pending" || promotion.status === "payment_pending") && (
                        <div className="mt-2">
                          <PromotionCancelButton promotionId={promotion.id} />
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="max-w-xs text-[#6B6B6B]">{promotion.reviewer_note ?? promotion.requester_note ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </section>
      </PageBody>
    </div>
  );
}
