"use client";
import { useTransition } from "react";
import { createPromotionCheckout } from "./actions";
import { Button } from "@/components/organizer/ui/button";

export function PromotionCheckoutButton({ promotionId }: { promotionId: string }) {
  const [pending, startTransition] = useTransition();
  return (
    <Button
      type="button"
      size="sm"
      onClick={() => startTransition(() => createPromotionCheckout(promotionId))}
      disabled={pending}
    >
      {pending ? "Öffnet…" : "Jetzt bezahlen"}
    </Button>
  );
}
