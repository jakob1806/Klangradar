import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { PromotionRequestForm } from "./promotion-request-form";
import { PromotionCheckoutButton } from "./promotion-checkout-button";

export const dynamic = "force-dynamic";

const PLACEMENT_LABEL: Record<string, string> = { standard: "Standard", featured: "Featured", local_spotlight: "Local Spotlight", homepage_feature: "Homepage Feature", push: "Push-Anfrage" };
const STATUS_LABEL: Record<string, string> = { pending: "In Prüfung", payment_pending: "Zahlung ausstehend", approved: "Freigegeben", rejected: "Abgelehnt", cancelled: "Storniert" };

interface EventRow { id: string; title: string; start_datetime: string; }
interface PromotionRow { id: string; placement: string; status: string; requester_note: string | null; reviewer_note: string | null; requested_at: string; events: { title: string; start_datetime: string } | null; }

export default async function PromotePage() {
  const supabase = await createClient();
  const now = new Date().toISOString();
  const [{ data: eventData }, { data: promotionData }] = await Promise.all([
    supabase.from("events").select("id, title, start_datetime").eq("status", "scheduled").gt("start_datetime", now).order("start_datetime", { ascending: true }).returns<EventRow[]>(),
    supabase.from("event_promotions").select("id, placement, status, requester_note, reviewer_note, requested_at, events(title, start_datetime)").order("requested_at", { ascending: false }).returns<PromotionRow[]>(),
  ]);
  const events = eventData ?? [];
  const promotions = promotionData ?? [];

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <div className="mb-8">
        <h1 className="type-heading text-2xl text-[#1d1d1f]">Push & Promote</h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Beantrage eine zusätzliche Sichtbarkeit für ein veröffentlichtes Event. Jede Platzierung wird vor der Aktivierung von der Redaktion geprüft.</p>
      </div>
      <section className="rounded-xl border border-black/[0.06] bg-[#f5f5f7] p-5">
        <h2 className="mb-4 text-base font-semibold text-[#1d1d1f]">Neue Promotion</h2>
        <PromotionRequestForm events={events.map((event) => ({ id: event.id, title: event.title, startLabel: formatMunichDateTime(event.start_datetime) }))} />
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
