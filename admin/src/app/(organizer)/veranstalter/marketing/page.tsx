import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";

export const dynamic = "force-dynamic";

interface AnalyticsRow { event_id: string; event_title: string; start_datetime: string; views: number; saves: number; shares: number; ticket_clicks: number; avg_view_duration_seconds: number | null; }

function number(value: number) { return new Intl.NumberFormat("de-DE").format(value); }

export default async function MarketingPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("organizer_event_analytics", { p_days: 30 });
  const rows = (data ?? []) as unknown as AnalyticsRow[];
  const totals = rows.reduce((all, row) => ({ views: all.views + Number(row.views), saves: all.saves + Number(row.saves), shares: all.shares + Number(row.shares), clicks: all.clicks + Number(row.ticket_clicks) }), { views: 0, saves: 0, shares: 0, clicks: 0 });
  const conversion = totals.views ? (totals.clicks / totals.views) * 100 : 0;

  return (
    <div className="mx-auto max-w-5xl px-6 py-10">
      <div className="flex flex-wrap items-start justify-between gap-4"><div><h1 className="type-heading text-2xl text-[#1d1d1f]">Marketing Center</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Performance deiner Events in den vergangenen 30 Tagen. Die Kennzahlen sind aggregiert und enthalten keine personenbezogenen Daten.</p></div><Link href="/veranstalter/promote" className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white hover:bg-[#0077ed]">Promotion planen</Link></div>
      {error ? <p className="mt-8 text-sm text-amber-700">Konnte Analytics nicht laden: {error.message}</p> : <><section className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"><Metric label="Event-Aufrufe" value={number(totals.views)} /><Metric label="Gespeicherte Events" value={number(totals.saves)} /><Metric label="Geteilt" value={number(totals.shares)} /><Metric label="Ticket-Klicks" value={number(totals.clicks)} detail={`${conversion.toFixed(1).replace(".", ",")} % der Aufrufe`} /></section><section className="mt-10"><div className="mb-3 flex items-baseline justify-between"><h2 className="text-sm font-semibold text-[#86868b]">Event-Performance</h2><span className="text-xs text-[#86868b]">Letzte 30 Tage</span></div>{rows.length === 0 ? <p className="text-sm text-[#86868b]">Noch keine messbaren Interaktionen für deine Events.</p> : <div className="overflow-x-auto rounded-xl border border-black/[0.06] bg-white"><table className="w-full text-sm"><thead className="border-b border-black/[0.06] text-left"><tr><th className="px-4 py-3 text-xs text-[#86868b]">Event</th><th className="px-4 py-3 text-right text-xs text-[#86868b]">Aufrufe</th><th className="px-4 py-3 text-right text-xs text-[#86868b]">Saves</th><th className="px-4 py-3 text-right text-xs text-[#86868b]">Shares</th><th className="px-4 py-3 text-right text-xs text-[#86868b]">Ticket-Klicks</th></tr></thead><tbody className="divide-y divide-neutral-200">{rows.map((row) => <tr key={row.event_id}><td className="px-4 py-3 font-medium text-[#1d1d1f]"><span className="block">{row.event_title}</span><span className="text-xs font-normal text-[#86868b]">{formatMunichDateTime(row.start_datetime)}</span></td><td className="px-4 py-3 text-right tabular-nums text-[#48484a]">{number(Number(row.views))}</td><td className="px-4 py-3 text-right tabular-nums text-[#48484a]">{number(Number(row.saves))}</td><td className="px-4 py-3 text-right tabular-nums text-[#48484a]">{number(Number(row.shares))}</td><td className="px-4 py-3 text-right tabular-nums font-medium text-[#1d1d1f]">{number(Number(row.ticket_clicks))}</td></tr>)}</tbody></table></div>}</section></>}
    </div>
  );
}

function Metric({ label, value, detail }: { label: string; value: string; detail?: string }) { return <div className="rounded-xl border border-black/[0.06] bg-white p-4"><p className="text-xs font-medium text-[#86868b]">{label}</p><p className="mt-1 text-2xl font-semibold tracking-tight text-[#1d1d1f]">{value}</p>{detail && <p className="mt-1 text-xs text-[#86868b]">{detail}</p>}</div>; }
