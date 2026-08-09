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
      className="border-2 border-[#171717] bg-[#171717] px-4 py-2 type-label !text-white hover:bg-white hover:!text-[#171717] disabled:opacity-50"
    >
      {pending ? pendingLabel : children}
    </button>
  );
}
