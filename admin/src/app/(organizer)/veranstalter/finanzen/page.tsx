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

type Promotion = {
  id: string;
  placement: string;
  status: string;
  payment_status: string;
  payment_amount_cents: number | null;
  payment_currency: string | null;
  requested_at: string;
  events: { title: string; start_datetime: string } | null;
};

function formatAmount(cents: number | null, currency: string | null) {
  if (cents === null) return "—";
  return new Intl.NumberFormat("de-DE", {
    style: "currency",
    currency: (currency ?? "eur").toUpperCase(),
  }).format(cents / 100);
}

function SummaryCard({ label, value, hint }: { label: string; value: string; hint: string }) {
  return <div className="rounded-2xl border border-black/[.06] bg-white p-5"><p className="text-sm text-[#86868b]">{label}</p><p className="mt-1 text-3xl font-semibold tracking-tight text-[#1d1d1f]">{value}</p><p className="mt-2 text-xs leading-5 text-[#86868b]">{hint}</p></div>;
}

export default async function FinancesPage() {
  const supabase = await createClient();
  await getEventOrganizerOptions();
  const { data, error } = await supabase
    .from("event_promotions")
    .select("id, placement, status, payment_status, payment_amount_cents, payment_currency, requested_at, events(title, start_datetime)")
    .order("requested_at", { ascending: false })
    .returns<Promotion[]>();
  const promotions = data ?? [];
  const paid = promotions.filter((promotion) => promotion.payment_status === "paid");
  const spendCents = paid.reduce((total, promotion) => total + (promotion.payment_amount_cents ?? 0), 0);
  const unknownHistoricalAmounts = paid.filter((promotion) => promotion.payment_amount_cents === null).length;
  const pending = promotions.filter((promotion) => promotion.status === "payment_pending").length;

  return <div className="mx-auto max-w-5xl px-6 py-10">
    <div className="flex flex-wrap items-end justify-between gap-4">
      <div><h1 className="type-heading text-2xl text-[#1d1d1f]">Finanzen</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Deine über Klangradar gebuchten Promotionen und die dazugehörigen Stripe-Zahlungen.</p></div>
      <Link href="/veranstalter/promote" className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white">Promotion buchen</Link>
    </div>

    {error ? <p className="mt-8 text-sm text-amber-700">Der Finanzbereich ist nach der nächsten Datenbank-Aktualisierung verfügbar.</p> : <>
      <div className="mt-8 grid gap-3 sm:grid-cols-3">
        <SummaryCard label="Bezahlte Ausgaben" value={formatAmount(spendCents, "EUR")} hint="Summe der gespeicherten Stripe-Zahlungen." />
        <SummaryCard label="Bezahlte Kampagnen" value={paid.length.toLocaleString("de-DE")} hint="Aktiv oder bereits abgeschlossen." />
        <SummaryCard label="Zahlung ausstehend" value={pending.toLocaleString("de-DE")} hint="Im Checkout noch nicht erfolgreich bezahlt." />
      </div>
      {unknownHistoricalAmounts > 0 && <p className="mt-4 text-xs leading-5 text-[#86868b]">Für {unknownHistoricalAmounts} frühere Zahlung{unknownHistoricalAmounts === 1 ? "" : "en"} wurde der Betrag noch nicht gespeichert. Neue Zahlungen werden automatisch vollständig erfasst.</p>}

      <section className="mt-10"><h2 className="text-lg font-semibold text-[#1d1d1f]">Kampagnenkosten</h2>
        {promotions.length === 0 ? <p className="mt-3 text-sm text-[#86868b]">Noch keine Promotionen gebucht.</p> : <div className="mt-3 overflow-hidden rounded-2xl border border-black/[.06] bg-white"><table className="w-full text-sm"><thead className="border-b border-black/[.06] text-left text-xs text-[#86868b]"><tr><th className="px-4 py-3">Kampagne</th><th className="px-4 py-3">Datum</th><th className="px-4 py-3">Zahlung</th><th className="px-4 py-3 text-right">Betrag</th></tr></thead><tbody className="divide-y divide-black/[.06]">{promotions.map((promotion) => <tr key={promotion.id}><td className="px-4 py-3"><p className="font-medium text-[#1d1d1f]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</p><p className="mt-0.5 text-xs text-[#86868b]">{promotion.events?.title ?? "Gelöschtes Event"}</p></td><td className="px-4 py-3 text-[#48484a]">{promotion.events ? formatMunichDateTime(promotion.events.start_datetime) : "—"}</td><td className="px-4 py-3 text-[#48484a]">{promotion.payment_status === "paid" ? "Bezahlt" : promotion.status === "payment_pending" ? "Ausstehend" : "Noch nicht fällig"}</td><td className="px-4 py-3 text-right font-medium tabular-nums text-[#1d1d1f]">{formatAmount(promotion.payment_amount_cents, promotion.payment_currency)}</td></tr>)}</tbody></table></div>}
      </section>
    </>}
  </div>;
}
