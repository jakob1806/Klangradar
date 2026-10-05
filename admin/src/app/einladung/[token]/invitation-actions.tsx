"use client";

import { useState, useTransition } from "react";
import { acceptInvitation, declineInvitation } from "./actions";

export function InvitationButtons({ token }: { token: string }) {
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function run(action: (token: string) => Promise<{ error: string } | never>) {
    setError(null);
    startTransition(async () => {
      const result = await action(token);
      if (result && "error" in result) setError(result.error);
    });
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-3 sm:flex-row">
        <button
          disabled={isPending}
          onClick={() => run(acceptInvitation)}
          className="h-12 flex-1 rounded-full bg-[#2D2A6E] px-6 text-[15px] font-bold text-white transition hover:bg-[#38358a] disabled:opacity-50"
        >
          {isPending ? "Einen Moment…" : "Einladung annehmen"}
        </button>
        <button
          disabled={isPending}
          onClick={() => run(declineInvitation)}
          className="h-12 flex-1 rounded-full border border-[#15131a]/15 bg-white px-6 text-[15px] font-bold text-[#15131a] transition hover:bg-[#15131a]/[0.03] disabled:opacity-50"
        >
          Ablehnen
        </button>
      </div>
      {error && (
        <p className="rounded-xl bg-[#BE185D]/10 px-4 py-3 text-sm text-[#a91551]" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
