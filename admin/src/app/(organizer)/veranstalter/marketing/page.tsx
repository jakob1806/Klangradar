import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";

export const dynamic = "force-dynamic";

const PLACEMENT_LABEL: Record<string, string> = {
  standard: "Standard",
  featured: "Featured",
  local_spotlight: "Local Spotlight",
  homepage_feature: "Homepage Feature",
  push: "Push-Anfrage",
};

type EventMetric = { event_id: string; title: string; start_datetime: string; views: number; saves: number; shares: number; ticket_clicks: number };
type Promotion = { id: string; placement: string; status: string; payment_status: string; requested_at: string; events: { id: string; title: string; start_datetime: string } | null };

function Metric({ label, value }: { label: string; value: number }) {
  return <div className="rounded-2xl border border-black/[.06] bg-white p-4"><p className="text-xs font-medium text-[#86868b]">{label}</p><p className="mt-1 text-2xl font-semibold tracking-tight text-[#1d1d1f]">{value.toLocaleString("de-DE")}</p></div>;
}

export default async function MarketingPage() {
  const supabase = await createClient();
  await getEventOrganizerOptions();
  const [{ data: promotionsData, error: promotionsError }, { data: metricsData, error: metricsError }] = await Promise.all([
    supabase.from("event_promotions").select("id, placement, status, payment_status, requested_at, events(id, title, start_datetime)").order("requested_at", { ascending: false }).returns<Promotion[]>(),
    supabase.rpc("organizer_event_metrics").returns<EventMetric[]>(),
  ]);
  const promotions = promotionsData ?? [];
  const metrics = Array.isArray(metricsData) ? metricsData : [];
  const metricByEvent = new Map(metrics.map((metric) => [metric.event_id, metric]));
  const active = promotions.filter((promotion) => promotion.status === "approved");
  const totals = metrics.reduce((sum, item) => ({ views: sum.views + Number(item.views), tickets: sum.tickets + Number(item.ticket_clicks), saves: sum.saves + Number(item.saves) }), { views: 0, tickets: 0, saves: 0 });

  return <div className="mx-auto max-w-5xl px-6 py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><h1 className="type-heading text-2xl text-[#1d1d1f]">Marketing Center</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Plane Sichtbarkeit und beobachte die Entwicklung deiner beworbenen Veranstaltungen.</p></div><Link href="/veranstalter/promote" className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white">Neue Kampagne</Link></div>
    {promotionsError || metricsError ? <p className="mt-8 text-sm text-amber-700">Das Marketing Center ist nach der nächsten Datenbank-Aktualisierung verfügbar.</p> : <>
      <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"><Metric label="Aktive Kampagnen" value={active.length} /><Metric label="Event-Aufrufe" value={totals.views} /><Metric label="Gespeichert" value={totals.saves} /><Metric label="Ticketlink-Klicks" value={totals.tickets} /></div>
      <p className="mt-3 text-xs leading-5 text-[#86868b]">Aufrufe, Saves und Ticket-Klicks zeigen aktuell die Gesamtentwicklung des jeweiligen Events, nicht nur Zugriffe aus einer einzelnen Kampagne. Kanalgenaue Reichweitenmessung wird als nächster Schritt ergänzt.</p>
      <section className="mt-10"><div className="flex items-baseline justify-between gap-3"><h2 className="text-lg font-semibold text-[#1d1d1f]">Kampagnen</h2><Link href="/veranstalter/finanzen" className="text-sm font-medium text-[#0071e3]">Kosten ansehen</Link></div>
        {promotions.length === 0 ? <p className="mt-3 text-sm text-[#86868b]">Noch keine Kampagnen angelegt.</p> : <div className="mt-3 grid gap-3">{promotions.map((promotion) => { const metric = promotion.events ? metricByEvent.get(promotion.events.id) : undefined; return <article key={promotion.id} className="rounded-2xl border border-black/[.06] bg-white p-5"><div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-semibold text-[#1d1d1f]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</p><p className="mt-1 text-sm text-[#48484a]">{promotion.events?.title ?? "Gelöschtes Event"}</p><p className="mt-1 text-xs text-[#86868b]">{promotion.events && formatMunichDateTime(promotion.events.start_datetime)}</p></div><span className="rounded-full bg-black/[.04] px-3 py-1 text-xs font-medium text-[#48484a]">{promotion.status === "approved" ? "Aktiv" : promotion.status === "payment_pending" ? "Zahlung ausstehend" : promotion.status === "rejected" ? "Abgelehnt" : "In Prüfung"}</span></div><div className="mt-4 flex flex-wrap gap-x-6 gap-y-2 text-sm text-[#48484a]"><span><strong className="text-[#1d1d1f]">{metric?.views ?? 0}</strong> Aufrufe</span><span><strong className="text-[#1d1d1f]">{metric?.ticket_clicks ?? 0}</strong> Ticket-Klicks</span><span><strong className="text-[#1d1d1f]">{metric?.saves ?? 0}</strong> Saves</span></div></article>; })}</div>}
      </section>
    </>}
  </div>;
}
