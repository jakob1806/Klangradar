import type { SupabaseClient } from "@supabase/supabase-js";

export type PromotionStats = {
  daysRunning: number;
  viewsDuring: number;
  extraViews: number;
  reachUplift: string;
  clicksDuring: number;
  extraClicks: number;
  clickUplift: string;
  impressions: number;
};

/** Wirkung einer Promotion: Laufzeit vs. Tagesschnitt der 14 Tage davor. */
export async function loadPromotionStats(supabase: SupabaseClient, promotionId: string): Promise<PromotionStats | null> {
  const { data, error } = await supabase.rpc("promotion_performance", { p_promotion_id: promotionId });
  const row = (data as Record<string, number | string>[] | null)?.[0];
  if (error || !row) return null;
  const days = Number(row.days_running);
  const views = Number(row.views_during);
  const clicks = Number(row.clicks_during);
  const expectedViews = Number(row.views_per_day_before) * days;
  const expectedClicks = Number(row.clicks_per_day_before) * days;
  return {
    daysRunning: days,
    viewsDuring: views,
    extraViews: Math.round(views - expectedViews),
    reachUplift: uplift(views, expectedViews),
    clicksDuring: clicks,
    extraClicks: Math.round(clicks - expectedClicks),
    clickUplift: uplift(clicks, expectedClicks),
    impressions: Number(row.impressions_during),
  };
}

function uplift(actual: number, expected: number): string {
  if (expected < 0.5) return actual > 0 ? `+${actual.toLocaleString("de-DE")}` : "±0";
  const pct = Math.round(((actual - expected) / expected) * 100);
  return `${pct >= 0 ? "+" : "−"}${Math.abs(pct).toLocaleString("de-DE")} %`;
}
