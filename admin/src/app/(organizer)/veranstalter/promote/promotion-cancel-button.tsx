"use client";

import { useState, useTransition } from "react";
import { cancelPromotion } from "./actions";

export function PromotionCancelButton({ promotionId }: { promotionId: string }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <div>
      <button
        type="button"
        disabled={pending}
        className="text-xs font-semibold text-[#a91551] hover:text-[#7a1929] disabled:opacity-50"
        onClick={() => {
          if (!window.confirm("Diese Promotion-Anfrage wirklich stornieren?")) return;
          setError(null);
          startTransition(async () => {
            const result = await cancelPromotion(promotionId);
            if (result.error) setError(result.error);
          });
        }}
      >
        {pending ? "Storniere…" : "Anfrage stornieren"}
      </button>
      {error && <p className="mt-1 text-xs text-[#a91551]">{error}</p>}
    </div>
  );
}
