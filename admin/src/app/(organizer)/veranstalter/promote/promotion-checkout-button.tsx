"use client";
import { useTransition } from "react";
import { createPromotionCheckout } from "./actions";
export function PromotionCheckoutButton({ promotionId }: { promotionId: string }) { const [pending, startTransition] = useTransition(); return <button onClick={() => startTransition(() => createPromotionCheckout(promotionId))} disabled={pending} className="mt-2 rounded-full bg-[#0071e3] px-3 py-1 text-xs font-semibold text-white disabled:opacity-50">{pending ? "Öffnet…" : "Jetzt bezahlen"}</button>; }
