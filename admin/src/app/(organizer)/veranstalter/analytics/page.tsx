import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";

export const dynamic = "force-dynamic";

type Metric = { event_id: string; title: string; start_datetime: string; views: number; saves: number; shares: number; ticket_clicks: number };

function MetricCard({ label, value }: { label: string; value: number }) {
  return <div className="rounded-2xl border border-black/[.06] bg-white p-5"><p className="text-sm text-[#86868b]">{label}</p><p className="mt-1 text-3xl font-semibold tracking-tight text-[#1d1d1f]">{value.toLocaleString("de-DE")}</p></div>;
}

function percentage(numerator: number, denominator: number) {
  if (denominator === 0) return "—";
  return new Intl.NumberFormat("de-DE", { style: "percent", maximumFractionDigits: 1 }).format(numerator / denominator);
}

export default async function AnalyticsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("organizer_event_metrics").returns<Metric[]>();
  const metrics: Metric[] = Array.isArray(data) ? data : [];
  const totals = metrics.reduce((sum, item) => ({ views: sum.views + Number(item.views), saves: sum.saves + Number(item.saves), shares: sum.shares + Number(item.shares), ticketClicks: sum.ticketClicks + Number(item.ticket_clicks) }), { views: 0, saves: 0, shares: 0, ticketClicks: 0 });
  const conversion = percentage(totals.ticketClicks, totals.views);

  return <div className="mx-auto max-w-5xl px-6 py-10">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><h1 className="type-heading text-2xl text-[#1d1d1f]">Analytics</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Aggregierte Kennzahlen deiner Veranstaltungen. Persönliche Daten einzelner Besucher werden nicht angezeigt.</p></div><Link href="/veranstalter/promote" className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white">Promotion planen</Link></div>
    {error ? <p className="mt-8 text-sm text-amber-700">Die Analytics sind nach der nächsten Datenbank-Aktualisierung verfügbar.</p> : <>
      <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-5"><MetricCard label="Event-Aufrufe" value={totals.views}/><MetricCard label="Gespeichert" value={totals.saves}/><MetricCard label="Geteilt" value={totals.shares}/><MetricCard label="Ticketlink-Klicks" value={totals.ticketClicks}/><div className="rounded-2xl border border-black/[.06] bg-white p-5"><p className="text-sm text-[#86868b]">Ticket-Conversion</p><p className="mt-1 text-3xl font-semibold tracking-tight text-[#1d1d1f]">{conversion}</p><p className="mt-1 text-xs text-[#86868b]">Ticket-Klicks / Aufrufe</p></div></div>
      <section className="mt-10"><h2 className="text-lg font-semibold text-[#1d1d1f]">Nach Veranstaltung</h2>{metrics.length === 0 ? <p className="mt-3 text-sm text-[#86868b]">Sobald deine Events aufgerufen werden, erscheinen die Kennzahlen hier.</p> : <div className="mt-3 overflow-hidden rounded-2xl border border-black/[.06] bg-white"><table className="w-full text-sm"><thead className="border-b border-black/[.06] text-left text-xs text-[#86868b]"><tr><th className="px-4 py-3">Event</th><th className="px-4 py-3">Aufrufe</th><th className="px-4 py-3">Saves</th><th className="px-4 py-3">Shares</th><th className="px-4 py-3">Tickets</th><th className="px-4 py-3">Conversion</th></tr></thead><tbody className="divide-y divide-black/[.06]">{metrics.map(item => <tr key={item.event_id}><td className="px-4 py-3"><Link className="font-medium text-[#1d1d1f] hover:text-[#0071e3]" href={`/veranstalter/events/${item.event_id}`}>{item.title}</Link><span className="mt-0.5 block text-xs text-[#86868b]">{formatMunichDateTime(item.start_datetime)}</span></td><td className="px-4 py-3 tabular-nums">{item.views}</td><td className="px-4 py-3 tabular-nums">{item.saves}</td><td className="px-4 py-3 tabular-nums">{item.shares}</td><td className="px-4 py-3 tabular-nums">{item.ticket_clicks}</td><td className="px-4 py-3 tabular-nums">{percentage(item.ticket_clicks, item.views)}</td></tr>)}</tbody></table></div>}</section>
    </>}
  </div>;
}
