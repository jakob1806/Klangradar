"use client";

import { useState, useTransition } from "react";
import { declineInvitation } from "./actions";

export function DeclineOnlyButton({ token }: { token: string }) {
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  return (
    <div>
      <button
        disabled={isPending}
        onClick={() =>
          startTransition(async () => {
            const result = await declineInvitation(token);
            if (result && "error" in result) setError(result.error);
          })
        }
        className="h-12 w-full rounded-full border border-[#111111]/15 bg-white px-6 text-[15px] font-bold text-[#111111] transition hover:bg-[#111111]/[0.03] disabled:opacity-50"
      >
        Ablehnen
      </button>
      {error && <p className="mt-2 text-sm text-[#a91551]">{error}</p>}
    </div>
  );
}
