"use client";

import { formatEuro, type PromotionQuote } from "@/lib/promotion-quote";

// Erstellt von Claude Code (29.10.2026): Live-Angebot im Promotion-Antrag —
// Summe, Laufzeit und Preisstaffeln nach Zeit bis zum Konzert.

const dayFormat = new Intl.DateTimeFormat("de-DE", { day: "numeric", month: "short", timeZone: "UTC" });
const formatDay = (day: string) => dayFormat.format(new Date(`${day}T12:00:00Z`));

function tierLabel(daysBefore: number) {
  if (daysBefore <= 7) return "letzte 7 Tage vor dem Konzert";
  if (daysBefore <= 30) return "8 bis 30 Tage vorher";
  return "mehr als 30 Tage vorher";
}

export function PromotionQuotePanel({
  quote,
  error,
  loading,
  flatPriceLabel,
}: {
  quote: PromotionQuote | null;
  error: string | null;
  loading: boolean;
  flatPriceLabel: string | null;
}) {
  if (error) return <p className="rounded-xl bg-[#FDECEA] px-4 py-3 text-sm text-[#B42318]">{error}</p>;
  if (!quote) return <p className="text-sm text-[#6B6B6B]">{loading ? "Berechne Angebot …" : ""}</p>;

  const included = quote.days.filter((day) => day.included);
  const skippedCap = quote.days.filter((day) => day.reason === "daily_cap").length;
  const skippedBudget = quote.days.filter((day) => day.reason === "budget").length;
  const tiers = [...included.reduce((map, day) => {
    const label = tierLabel(day.days_before);
    const entry = map.get(label) ?? { label, days: 0, rate: day.rate_cents, total: 0 };
    entry.days += 1;
    entry.total += day.rate_cents;
    return map.set(label, entry);
  }, new Map<string, { label: string; days: number; rate: number; total: number }>()).values()];

  return (
    <section aria-live="polite" className={`rounded-2xl border border-[#2D2A6E]/15 bg-[#F7F7FD] p-5 transition-opacity ${loading ? "opacity-60" : ""}`}>
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <div>
          <p className="text-[13px] font-medium text-[#6B6B6B]">{quote.dynamic ? "Dein Angebot" : "Laufzeit"}</p>
          <p className="text-sm text-[#111111]">
            {quote.days_included === 0
              ? "Kein Tag im Budget"
              : quote.unit === "push"
                ? `Push am ${formatDay(quote.first_day!)}`
                : `${quote.days_included} ${quote.days_included === 1 ? "Tag" : "Tage"} · ${formatDay(quote.first_day!)} bis ${formatDay(quote.last_day!)}`}
          </p>
        </div>
        <p className="text-3xl font-semibold tracking-tight text-[#111111] tabular-nums">
          {quote.dynamic ? formatEuro(quote.amount_cents) : flatPriceLabel ?? "Preis im Checkout"}
        </p>
      </div>

      {quote.dynamic && tiers.length > 0 && (
        <ul className="mt-4 flex flex-col gap-1.5 border-t border-[#2D2A6E]/10 pt-3 text-[13px] text-[#4A4A4A]">
          {tiers.map((tier) => (
            <li key={tier.label} className="flex justify-between gap-3">
              <span>
                {quote.unit === "push" ? "Versand" : `${tier.days} × ${formatEuro(tier.rate)}`} · {tier.label}
              </span>
              <span className="tabular-nums">{formatEuro(tier.total)}</span>
            </li>
          ))}
        </ul>
      )}

      {(skippedCap > 0 || skippedBudget > 0) && (
        <p className="mt-3 text-xs text-[#6B6B6B]">
          {[
            skippedCap > 0 && `${skippedCap} ${skippedCap === 1 ? "Tag liegt" : "Tage liegen"} über dem Tagesbudget und ${skippedCap === 1 ? "wird" : "werden"} ausgelassen`,
            skippedBudget > 0 && `${skippedBudget} frühere ${skippedBudget === 1 ? "Tag passt" : "Tage passen"} nicht mehr ins Gesamtbudget`,
          ]
            .filter(Boolean)
            .join(" · ") + "."}
        </p>
      )}
      <p className="mt-3 text-xs text-[#6B6B6B]">
        {quote.dynamic
          ? "Je näher das Konzert, desto höher der Tagespreis. Abgerechnet wird beim Bezahlen. Tage, die bis dahin vorbei sind, entfallen."
          : "Abrechnung zum Festpreis der Platzierung, Laufzeit und Zielgruppe gelten wie gewählt."}
      </p>
    </section>
  );
}
