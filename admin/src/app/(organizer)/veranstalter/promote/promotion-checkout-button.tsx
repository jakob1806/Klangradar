"use client";
import { useState, useTransition } from "react";
import { createPromotionCheckout } from "./actions";
import { Button } from "@/components/organizer/ui/button";

export function PromotionCheckoutButton({ promotionId, priceLabel }: { promotionId: string; priceLabel?: string }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <div className="flex flex-col gap-1">
      <Button
        type="button"
        size="sm"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            setError(null);
            const result = await createPromotionCheckout(promotionId);
            if (result.url) window.location.assign(result.url);
            else setError(result.error ?? "Unbekannter Fehler.");
          })
        }
      >
        {pending ? "Öffnet…" : priceLabel ? `Jetzt ${priceLabel} bezahlen` : "Jetzt bezahlen"}
      </Button>
      {error && <p className="max-w-[16rem] text-xs text-[#a12626]">{error}</p>}
    </div>
  );
}
