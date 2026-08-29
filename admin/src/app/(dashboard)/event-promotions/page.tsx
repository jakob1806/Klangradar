import { createClient } from "@/lib/supabase/server";
import { PromotionList, type UiPromotion } from "./promotion-list";

export const dynamic = "force-dynamic";

interface PromotionRow { id: string; placement: string; requester_note: string | null; requested_at: string; requested_by: string; events: { title: string; start_datetime: string } | null; }

export default async function EventPromotionsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.from("event_promotions").select("id, placement, requester_note, requested_at, requested_by, events(title, start_datetime)").eq("status", "pending").order("requested_at", { ascending: true }).returns<PromotionRow[]>();
  const promotions = data ?? [];
  const userIds = [...new Set(promotions.map((promotion) => promotion.requested_by))];
  const { data: profiles } = userIds.length ? await supabase.from("profiles").select("id, display_name").in("id", userIds) : { data: [] };
  const profileNames = new Map((profiles ?? []).map((profile) => [profile.id as string, (profile.display_name as string | null) ?? profile.id as string]));
  const items: UiPromotion[] = promotions.map((promotion) => ({ id: promotion.id, eventTitle: promotion.events?.title ?? "Gelöschtes Event", eventStart: promotion.events?.start_datetime ?? promotion.requested_at, placement: promotion.placement, requester: profileNames.get(promotion.requested_by) ?? promotion.requested_by, requesterNote: promotion.requester_note, requestedAt: promotion.requested_at }));

  return <div className="p-8"><div><h1 className="text-xl font-semibold tracking-tight">Event-Promotions</h1><p className="mt-1 max-w-2xl text-sm text-neutral-500">Anträge für zusätzliche Sichtbarkeit. Freigaben gelten ab sofort bis zum Beginn des jeweiligen Events; Push-Anfragen werden nie automatisch versendet.</p><p className="mt-2 text-xs text-neutral-500">{items.length} offen</p></div>{error && <p className="mt-6 text-sm text-amber-700">Konnte Promotionen nicht laden: {error.message}</p>}{!error && <div className="mt-6"><PromotionList promotions={items} /></div>}</div>;
}
