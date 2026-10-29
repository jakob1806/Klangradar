import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import { AdminPageHeader, TableFrame, Th, inputClass, tbodyClass, theadClass } from "@/components/admin-kit";
import { getPlacementPriceLabels } from "@/lib/promotion-payment";
import { savePromotionPricing } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Preise der
// Promotionen je Tag, gestaffelt nach Zeit bis zum Konzert. Solange die
// Staffelpreise aus sind, kassiert der Checkout die festen Stripe-Preise.

const PLACEMENTS = [
  { key: "standard", label: "Standard", unit: "pro Tag" },
  { key: "featured", label: "Featured", unit: "pro Tag" },
  { key: "local_spotlight", label: "Local Spotlight", unit: "pro Tag" },
  { key: "homepage_feature", label: "Homepage Feature", unit: "pro Tag" },
  { key: "push", label: "Push", unit: "pro Versand" },
];

const TIERS = [
  { min: 31, label: "ab 31 Tagen vorher" },
  { min: 8, label: "8–30 Tage vorher" },
  { min: 0, label: "letzte 7 Tage" },
];

interface Tier {
  placement: string;
  min_days_before: number;
  rate_cents: number;
}

export default async function PromotionPricingPage() {
  const supabase = await createClient();
  const [{ data: settings }, { data: tierData }, flatPrices] = await Promise.all([
    supabase.from("promotion_pricing_settings").select("dynamic_enabled, updated_at").maybeSingle(),
    supabase.from("promotion_price_tiers").select("placement, min_days_before, rate_cents"),
    getPlacementPriceLabels(),
  ]);
  const tiers = (tierData ?? []) as Tier[];
  const rate = (placement: string, min: number) => tiers.find((tier) => tier.placement === placement && tier.min_days_before === min)?.rate_cents;
  const enabled = Boolean(settings?.dynamic_enabled);

  return (
    <div className="p-8">
      <AdminPageHeader
        title="Promotion-Preise"
        description="Tagespreise für Promotionen, gestaffelt nach Zeit bis zum Konzert: Je näher das Konzert, desto wertvoller die Platzierung. Veranstalter wählen Laufzeit, Tages- und Gesamtbudget und Zielgruppe; das Angebot rechnet mit diesen Staffeln."
      />

      <form action={savePromotionPricing} className="mt-6 flex flex-col gap-6">
        <label
          className={`flex items-start gap-3 rounded-xl border p-4 shadow-sm ${enabled ? "border-emerald-200 bg-emerald-50" : "border-amber-200 bg-amber-50"}`}
        >
          <input type="checkbox" name="dynamic_enabled" defaultChecked={enabled} className="mt-0.5 size-4 accent-[#2D2A6E]" />
          <span className="text-sm">
            <span className="block font-medium text-neutral-900">Staffelpreise im Checkout verwenden</span>
            <span className="text-neutral-600">
              {enabled
                ? "Aktiv: Veranstalter zahlen den Betrag aus Laufzeit × Staffelpreis."
                : "Aus: Der Checkout nutzt weiter die festen Stripe-Preise. Laufzeit, Budgets und Zielgruppe wirken trotzdem."}
            </span>
          </span>
        </label>

        <TableFrame>
          <table className="w-full text-sm">
            <thead className={theadClass}>
              <tr>
                <Th>Platzierung</Th>
                {TIERS.map((tier) => (
                  <Th key={tier.min}>{tier.label}</Th>
                ))}
                <Th>Fester Stripe-Preis</Th>
              </tr>
            </thead>
            <tbody className={tbodyClass}>
              {PLACEMENTS.map((placement) => (
                <tr key={placement.key}>
                  <td className="px-4 py-3">
                    <p className="font-medium text-neutral-900">{placement.label}</p>
                    <p className="text-xs text-neutral-500">Euro {placement.unit}</p>
                  </td>
                  {TIERS.map((tier) => {
                    const cents = rate(placement.key, tier.min);
                    return (
                      <td key={tier.min} className="px-4 py-3">
                        <input
                          name={`rate:${placement.key}:${tier.min}`}
                          inputMode="decimal"
                          aria-label={`${placement.label}, ${tier.label}`}
                          defaultValue={cents != null ? (cents / 100).toFixed(2).replace(".", ",") : ""}
                          className={`${inputClass} w-24 text-right tabular-nums`}
                        />
                      </td>
                    );
                  })}
                  <td className="px-4 py-3 text-neutral-500">{flatPrices[placement.key] ?? "–"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </TableFrame>

        <div className="flex items-center gap-3">
          <SubmitButton>Preise speichern</SubmitButton>
          {settings?.updated_at && (
            <span className="text-xs text-neutral-500">
              Zuletzt geändert {new Intl.DateTimeFormat("de-DE", { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Berlin" }).format(new Date(settings.updated_at))}
            </span>
          )}
        </div>
      </form>
    </div>
  );
}
