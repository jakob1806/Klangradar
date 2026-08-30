import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { PromotionRequestForm } from "./promotion-request-form";
import { PromotionCheckoutButton } from "./promotion-checkout-button";
import { getPromotableEvents } from "./promotable-events";
import { getStripe } from "@/lib/stripe";

export const dynamic = "force-dynamic";

const PLACEMENT_LABEL: Record<string, string> = { standard: "Standard", featured: "Featured", local_spotlight: "Local Spotlight", homepage_feature: "Homepage Feature", push: "Push-Anfrage" };
const STATUS_LABEL: Record<string, string> = { pending: "In Prüfung", payment_pending: "Zahlung ausstehend", approved: "Freigegeben", rejected: "Abgelehnt", cancelled: "Storniert" };
const PRICE_ID_BY_PLACEMENT: Record<string, string> = { standard: "price_1U9otxCkrdnLOI0hTRLkOdoW", featured: "price_1U9ouVCkrdnLOI0hCbzW8jWj", local_spotlight: "price_1U9oukCkrdnLOI0hBkihCzyF", push: "price_1U9ov5CkrdnLOI0hFUwOpA6i", homepage_feature: "price_1U9ovMCkrdnLOI0hqkPMYDag" };

interface PromotionRow { id: string; placement: string; status: string; requester_note: string | null; reviewer_note: string | null; requested_at: string; events: { title: string; start_datetime: string } | null; }

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
    <div className="mx-auto max-w-4xl px-6 py-10">
      <div className="mb-8">
        <h1 className="type-heading text-2xl text-[#1d1d1f]">Push & Promote</h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Wähle ein kommendes Event aus deinen eigenen Terminen oder den Terminen beanspruchter Profile. Nach redaktioneller Freigabe erhältst du den Zahlungslink; die Platzierung startet erst nach erfolgreicher Zahlung.</p>
      </div>
      <section className="rounded-xl border border-black/[0.06] bg-[#f5f5f7] p-5">
        <h2 className="mb-4 text-base font-semibold text-[#1d1d1f]">Neue Promotion</h2>
        {eventError ? (
          <p className="text-sm text-amber-800">Deine Events konnten gerade nicht geladen werden. Bitte lade die Seite erneut; die Events selbst sind nicht verloren. ({eventError})</p>
        ) : (
          <PromotionRequestForm events={events.map((event) => ({ ...event, startLabel: formatMunichDateTime(event.startDatetime) }))} priceLabels={priceLabels} />
        )}
      </section>
      <section className="mt-10">
        <h2 className="mb-3 text-sm font-semibold text-[#86868b]">Meine Anfragen</h2>
        {promotions.length === 0 ? <p className="text-sm text-[#86868b]">Noch keine Promotionen beantragt.</p> : (
          <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white"><table className="w-full text-sm"><thead className="border-b border-black/[0.06] text-left"><tr><th className="px-4 py-3 text-xs text-[#86868b]">Event</th><th className="px-4 py-3 text-xs text-[#86868b]">Platzierung</th><th className="px-4 py-3 text-xs text-[#86868b]">Status</th><th className="px-4 py-3 text-xs text-[#86868b]">Hinweis</th></tr></thead><tbody className="divide-y divide-neutral-200">{promotions.map((promotion) => <tr key={promotion.id}><td className="px-4 py-3 font-medium text-[#1d1d1f]"><span className="block">{promotion.events?.title ?? "Gelöschtes Event"}</span><span className="text-xs font-normal text-[#86868b]">{promotion.events && formatMunichDateTime(promotion.events.start_datetime)}</span></td><td className="px-4 py-3 text-[#48484a]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</td><td className="px-4 py-3 text-[#48484a]"><span className="block">{STATUS_LABEL[promotion.status] ?? promotion.status}</span>{promotion.status === "payment_pending" && <PromotionCheckoutButton promotionId={promotion.id} />}</td><td className="max-w-xs px-4 py-3 text-[#86868b]">{promotion.reviewer_note ?? promotion.requester_note ?? "—"}</td></tr>)}</tbody></table></div>
        )}
      </section>
    </div>
  );
}
