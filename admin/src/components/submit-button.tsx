"use client";

import { useFormStatus } from "react-dom";

export function SubmitButton({
  children,
  pendingLabel = "Speichere…",
}: {
  children: React.ReactNode;
  pendingLabel?: string;
}) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-lg bg-[#2D2A6E] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#38358a] disabled:opacity-50"
    >
      {pending ? pendingLabel : children}
    </button>
  );
}
