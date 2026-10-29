"use client";

import { useActionState } from "react";
import { cn } from "@/lib/utils";

// Erstellt von Claude Code (29.10.2026): Formular für Server Actions, die
// { error } oder { success } zurückgeben — zeigt die Meldung direkt unter dem
// Formular statt einer Fehlerseite (Abos, Werkeinführungen, Tickets,
// Besetzung im Veranstalterportal).
export type ActionResult = { error?: string; success?: string } | null;

export function ActionForm({
  action,
  children,
  className,
}: {
  action: (state: ActionResult, formData: FormData) => Promise<ActionResult>;
  children: React.ReactNode;
  className?: string;
}) {
  const [state, formAction] = useActionState(action, null);
  return (
    <form action={formAction} className={className}>
      {children}
      {state?.error && (
        <p role="alert" className="text-[13px] text-[#B42318] sm:basis-full">
          {state.error}
        </p>
      )}
      {state?.success && (
        <p role="status" className={cn("text-[13px] text-[#1F7A4D] sm:basis-full")}>
          {state.success}
        </p>
      )}
    </form>
  );
}
