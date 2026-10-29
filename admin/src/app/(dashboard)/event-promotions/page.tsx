import { createClient } from "@/lib/supabase/server";
import { PromotionList, type UiPromotion } from "./promotion-list";

export const dynamic = "force-dynamic";

interface PromotionRow { id: string; placement: string; run_start: string | null; run_end: string | null; daily_cap_cents: number | null; total_budget_cents: number | null; target_audiences: string[] | null; quoted_amount_cents: number | null; requester_note: string | null; requested_at: string; requested_by: string; events: { title: string; start_datetime: string } | null; }

// Erweiterung (Claude Code, 29.10.2026): Laufzeit, Budgets und Zielgruppe
// der Anfrage für die Prüfung sichtbar machen.
const AUDIENCE_LABEL: Record<string, string> = { followers: "Fans", genre: "Genre-Interessierte", composers: "Komponist:innen-Hörer:innen" };
function promotionDetails(row: PromotionRow): string | null {
  const euro = (cents: number) => new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(cents / 100);
  const parts = [
    row.run_start && row.run_end && (row.run_start === row.run_end ? `am ${row.run_start}` : `${row.run_start} bis ${row.run_end}`),
    row.daily_cap_cents && `max. ${euro(row.daily_cap_cents)}/Tag`,
    row.total_budget_cents && `Budget ${euro(row.total_budget_cents)}`,
    row.quoted_amount_cents != null && `Angebot ${euro(row.quoted_amount_cents)}`,
    row.target_audiences?.length ? `Zielgruppe: ${row.target_audiences.map((value) => AUDIENCE_LABEL[value] ?? value).join(", ")}` : null,
  ].filter(Boolean);
  return parts.length ? parts.join(" · ") : null;
}

interface DecidedRow { id: string; placement: string; status: string; payment_status: string | null; payment_amount_cents: number | null; payment_currency: string | null; reviewed_at: string | null; payment_reminder_sent_at: string | null; ends_at: string | null; events: { title: string; start_datetime: string } | null; }

const PLACEMENT: Record<string, string> = { standard: "Standard", featured: "Featured", local_spotlight: "Local Spotlight", homepage_feature: "Homepage Feature", push: "Push-Anfrage" };
const fmt = (iso: string | null) => (iso ? new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" }) : "—");

function DecidedTable({ rows }: { rows: DecidedRow[] }) {
  return (
    <section className="mt-12">
      <h2 className="text-base font-semibold">Freigegeben &amp; Zahlungsstatus</h2>
      <p className="mt-1 text-xs text-neutral-500">Unbezahlte Freigaben werden nach 3 Tagen per Mail erinnert und verfallen automatisch bei Konzertbeginn.</p>
      {rows.length === 0 ? (
        <p className="mt-4 text-sm text-neutral-400">Keine freigegebenen Promotionen.</p>
      ) : (
        <div className="mt-4 overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
          <table className="w-full text-sm">
            <thead className="border-b border-black/[0.06] text-left">
              <tr><th className="type-label px-4 py-3">Event</th><th className="type-label px-4 py-3">Platzierung</th><th className="type-label px-4 py-3">Zahlung</th><th className="type-label px-4 py-3">Freigegeben</th><th className="type-label px-4 py-3">Läuft bis</th></tr>
            </thead>
            <tbody className="divide-y divide-neutral-200">
              {rows.map((row) => (
                <tr key={row.id}>
                  <td className="px-4 py-3 font-medium text-neutral-900">{row.events?.title ?? "Gelöschtes Event"}<span className="block text-xs font-normal text-neutral-500">{fmt(row.events?.start_datetime ?? null)}</span></td>
                  <td className="px-4 py-3 text-neutral-600">{PLACEMENT[row.placement] ?? row.placement}</td>
                  <td className="px-4 py-3">
                    {row.payment_status === "paid" ? (
                      <span className="font-medium text-emerald-700">Bezahlt{row.payment_amount_cents != null ? ` · ${new Intl.NumberFormat("de-DE", { style: "currency", currency: (row.payment_currency ?? "eur").toUpperCase() }).format(row.payment_amount_cents / 100)}` : ""}</span>
                    ) : (
                      <span className="font-medium text-amber-700">Ausstehend{row.payment_reminder_sent_at ? " · erinnert" : ""}</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-neutral-600">{fmt(row.reviewed_at)}</td>
                  <td className="px-4 py-3 text-neutral-600">{row.status === "approved" ? fmt(row.ends_at) : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

export default async function EventPromotionsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.from("event_promotions").select("id, placement, run_start, run_end, daily_cap_cents, total_budget_cents, target_audiences, quoted_amount_cents, requester_note, requested_at, requested_by, events(title, start_datetime)").eq("status", "pending").order("requested_at", { ascending: true }).returns<PromotionRow[]>();
  const promotions = data ?? [];
  const userIds = [...new Set(promotions.map((promotion) => promotion.requested_by))];
  const { data: profiles } = userIds.length ? await supabase.from("profiles").select("id, display_name").in("id", userIds) : { data: [] };
  const profileNames = new Map((profiles ?? []).map((profile) => [profile.id as string, (profile.display_name as string | null) ?? profile.id as string]));
  const items: UiPromotion[] = promotions.map((promotion) => ({ id: promotion.id, eventTitle: promotion.events?.title ?? "Gelöschtes Event", eventStart: promotion.events?.start_datetime ?? promotion.requested_at, placement: promotion.placement, requester: profileNames.get(promotion.requested_by) ?? promotion.requested_by, requesterNote: promotion.requester_note, requestedAt: promotion.requested_at, details: promotionDetails(promotion) }));

  // Freigegebene/aktive Promotionen mit Zahlungsstatus: vorher war nicht zu
  // sehen, wer freigegeben, aber (noch) nicht bezahlt hat.
  const { data: decided } = await supabase
    .from("event_promotions")
    .select("id, placement, status, payment_status, payment_amount_cents, payment_currency, reviewed_at, payment_reminder_sent_at, ends_at, events(title, start_datetime)")
    .in("status", ["payment_pending", "approved"])
    .order("reviewed_at", { ascending: false })
    .limit(50)
    .returns<DecidedRow[]>();

  return <div className="p-8"><div><h1 className="text-xl font-semibold tracking-tight">Event-Promotions</h1><p className="mt-1 max-w-2xl text-sm text-neutral-500">Prüfe Anträge und gib bei Zustimmung ausschließlich den Zahlungslink frei. Sichtbarkeit startet erst nach bestätigter Stripe-Zahlung; Push-Anfragen werden nie automatisch versendet.</p><p className="mt-2 text-xs text-neutral-500">{items.length} offen</p></div>{error && <p className="mt-6 text-sm text-amber-700">Konnte Promotionen nicht laden: {error.message}</p>}{!error && <div className="mt-6"><PromotionList promotions={items} /></div>}<DecidedTable rows={decided ?? []} /></div>;
}
