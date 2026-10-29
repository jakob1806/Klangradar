import type { SupabaseClient } from "@supabase/supabase-js";
import { munichLocalToISOString } from "@/lib/munich-time";

// Erstellt von Claude Code (29.10.2026): Angebot für eine Promotion aus der
// Datenbankfunktion promotion_quote (eine Quelle für Formular, Antrag und
// Checkout). Preise je Tag nach Zeit bis zum Konzert, Budgets und Laufzeit.

export type QuoteDay = { day: string; days_before: number; rate_cents: number; included: boolean; reason?: "daily_cap" | "budget" };

export type PromotionQuote = {
  dynamic: boolean;
  unit: "day" | "push";
  concert_day: string;
  first_day: string | null;
  last_day: string | null;
  days_included: number;
  amount_cents: number;
  days: QuoteDay[];
};

export type QuoteParams = {
  eventId: string;
  placement: string;
  start: string | null;
  end: string | null;
  dailyCapCents: number | null;
  totalBudgetCents: number | null;
};

export const TARGET_AUDIENCES = [
  { value: "followers", label: "Fans der Mitwirkenden und des Orts", description: "Folgen einer beteiligten Person, einem Ensemble oder der Spielstätte." },
  { value: "genre", label: "Genre-Interessierte", description: "Haben im Profil ein Genre des Konzerts als Interesse gewählt." },
  { value: "composers", label: "Hörer:innen der Komponist:innen", description: "Folgen einer Komponist:in des Programms oder haben Konzerte mit ihr gemerkt." },
] as const;

export async function fetchPromotionQuote(supabase: SupabaseClient, params: QuoteParams): Promise<{ quote?: PromotionQuote; error?: string }> {
  const { data, error } = await supabase.rpc("promotion_quote", {
    p_event_id: params.eventId,
    p_placement: params.placement,
    p_start: params.start || null,
    p_end: params.end || null,
    p_daily_cap_cents: params.dailyCapCents,
    p_total_budget_cents: params.totalBudgetCents,
  });
  if (error) return { error: error.message };
  const result = data as (PromotionQuote & { error?: string }) | null;
  if (!result) return { error: "Kein Angebot möglich." };
  if (result.error) return { error: result.error };
  return { quote: result };
}

/** Euro-Eingabe ("12,50") → Cent; leer → null. */
export function euroToCents(value: FormDataEntryValue | string | null): number | null | "invalid" {
  const raw = String(value ?? "").trim().replace(/\s/g, "").replace(",", ".");
  if (!raw) return null;
  const number = Number(raw);
  if (!Number.isFinite(number) || number <= 0 || number > 100000) return "invalid";
  return Math.round(number * 100);
}

export function formatEuro(cents: number) {
  return new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(cents / 100);
}

/** Laufzeit in Zeitpunkte für event_promotions.starts_at/ends_at (Münchner Tage). */
export function promotionWindow(runStart: string | null, runEnd: string | null, concertIso: string | null, nowIso = new Date().toISOString()) {
  const startIso = runStart ? munichLocalToISOString(`${runStart}T00:00`) : nowIso;
  const startsAt = startIso > nowIso ? startIso : nowIso;
  const dayAfterEnd = runEnd ? new Date(`${runEnd}T12:00:00Z`) : null;
  if (dayAfterEnd) dayAfterEnd.setUTCDate(dayAfterEnd.getUTCDate() + 1);
  const endIso = dayAfterEnd ? munichLocalToISOString(`${dayAfterEnd.toISOString().slice(0, 10)}T00:00`) : null;
  const endsAt = [endIso, concertIso].filter((value): value is string => Boolean(value)).sort()[0] ?? null;
  return { startsAt, endsAt };
}
