"use client";

import { useFormStatus } from "react-dom";
import { Button, type ButtonProps } from "@/components/organizer/ui/button";

// Portal-eigener Submit-Button statt @/components/submit-button (Apple-Blau,
// vom internen Redaktions-Dashboard mitbenutzt — bewusst NICHT angefasst,
// damit /admin unverändert bleibt). Gleiche useFormStatus-Pending-Logik,
// aber in der Button-Komponente des Veranstalter-Designsystems.
export function SubmitButton({
  children,
  pendingLabel = "Speichere…",
  ...props
}: ButtonProps & { pendingLabel?: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending} {...props}>
      {pending ? pendingLabel : children}
    </Button>
  );
}
