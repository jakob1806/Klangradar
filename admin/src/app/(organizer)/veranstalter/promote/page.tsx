import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { PromotionRequestForm } from "./promotion-request-form";
import { PromotionCheckoutButton } from "./promotion-checkout-button";
import { getPromotableEvents } from "./promotable-events";
import { getStripe } from "@/lib/stripe";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/organizer/ui/table";
import { Steps } from "@/components/organizer/ui/steps";

export const dynamic = "force-dynamic";

const PLACEMENT_LABEL: Record<string, string> = { standard: "Standard", featured: "Featured", local_spotlight: "Local Spotlight", homepage_feature: "Homepage Feature", push: "Push-Anfrage" };
const STATUS_LABEL: Record<string, string> = { pending: "In Prüfung", payment_pending: "Zahlung ausstehend", approved: "Freigegeben", rejected: "Abgelehnt", cancelled: "Storniert" };
const PRICE_ID_BY_PLACEMENT: Record<string, string> = { standard: "price_1U9otxCkrdnLOI0hTRLkOdoW", featured: "price_1U9ouVCkrdnLOI0hCbzW8jWj", local_spotlight: "price_1U9oukCkrdnLOI0hBkihCzyF", push: "price_1U9ov5CkrdnLOI0hFUwOpA6i", homepage_feature: "price_1U9ovMCkrdnLOI0hqkPMYDag" };
const PROMOTION_STEPS = ["Angefragt", "Freigabe", "Zahlung", "Aktiv"];

interface PromotionRow { id: string; placement: string; status: string; requester_note: string | null; reviewer_note: string | null; requested_at: string; events: { title: string; start_datetime: string } | null; }

function statusVariant(status: string): "success" | "warning" | "danger" | "default" {
  if (status === "approved") return "success";
  if (status === "payment_pending") return "warning";
  if (status === "rejected" || status === "cancelled") return "danger";
  return "default";
}

// Bildet den Promotion-Status auf den Fortschritts-Indikator ab — "pending"
// steht noch ganz am Anfang (Redaktion prüft erst), "approved" ist technisch
// erst nach erfolgreicher Zahlung wirklich aktiv (siehe promote/page.tsx
// oben: "die Platzierung startet erst nach erfolgreicher Zahlung").
function promotionStepIndex(status: string): { currentIndex: number; haltedAt?: number } {
  switch (status) {
    case "pending":
      return { currentIndex: 0 };
    case "payment_pending":
      return { currentIndex: 2 };
    case "approved":
      return { currentIndex: 3 };
    case "rejected":
      return { currentIndex: 0, haltedAt: 1 };
    case "cancelled":
      return { currentIndex: 0, haltedAt: 2 };
    default:
      return { currentIndex: 0 };
  }
}

export default async function PromotePage() {
  const supabase = await createClient();
  const [{ events, error: eventError }, { data: promotionData }, priceLabels] = await Promise.all([
    getPromotableEvents(),
    supabase.from("event_promotions").select("id, placement, status, requester_note, reviewer_note, requested_at, events(title, start_datetime)").order("requested_at", { ascending: false }).returns<PromotionRow[]>(),
    (async () => {
      try {
        const prices = await Promise.all(Object.entries(PRICE_ID_BY_PLACEMENT).map(async ([placement, priceId]) => {
          const price = await getStripe().prices.retrieve(priceId);
          const label = price.unit_amount == null ? null : new Intl.NumberFormat("de-DE", { style: "currency", currency: price.currency.toUpperCase() }).format(price.unit_amount / 100);
          return [placement, label] as const;
        }));
        return Object.fromEntries(prices.filter((entry): entry is [string, string] => Boolean(entry[1])));
      } catch {
        return {} as Record<string, string>;
      }
    })(),
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
          <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Meine Anfragen</h2>
          {promotions.length === 0 ? (
            <Card>
              <CardContent className="pt-5 text-sm text-[#726c78]">Noch keine Promotionen beantragt.</CardContent>
            </Card>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Event</TableHead>
                  <TableHead>Platzierung</TableHead>
                  <TableHead>Verlauf</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Hinweis</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {promotions.map((promotion) => {
                  const { currentIndex, haltedAt } = promotionStepIndex(promotion.status);
                  return (
                    <TableRow key={promotion.id}>
                      <TableCell className="font-medium text-[#15131a]">
                        <span className="block">{promotion.events?.title ?? "Gelöschtes Event"}</span>
                        <span className="text-xs font-normal text-[#726c78]">{promotion.events && formatMunichDateTime(promotion.events.start_datetime)}</span>
                      </TableCell>
                      <TableCell className="text-[#4a4550]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</TableCell>
                      <TableCell>
                        <Steps steps={PROMOTION_STEPS} currentIndex={currentIndex} haltedAt={haltedAt} />
                      </TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(promotion.status)}>{STATUS_LABEL[promotion.status] ?? promotion.status}</Badge>
                        {promotion.status === "payment_pending" && (
                          <div className="mt-2">
                            <PromotionCheckoutButton promotionId={promotion.id} />
                          </div>
                        )}
                      </TableCell>
                      <TableCell className="max-w-xs text-[#726c78]">{promotion.reviewer_note ?? promotion.requester_note ?? "—"}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </section>
      </PageBody>
    </div>
  );
}
