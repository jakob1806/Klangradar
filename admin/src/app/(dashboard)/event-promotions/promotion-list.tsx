"use client";

import { useState, useTransition } from "react";
import { reviewPromotion } from "./actions";

export interface UiPromotion { id: string; eventTitle: string; eventStart: string; placement: string; requester: string; requesterNote: string | null; requestedAt: string; }

const PLACEMENT_LABEL: Record<string, string> = { standard: "Standard", featured: "Featured", local_spotlight: "Local Spotlight", homepage_feature: "Homepage Feature", push: "Push-Anfrage" };
function formatDate(iso: string) { return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" }); }

export function PromotionList({ promotions }: { promotions: UiPromotion[] }) {
  const [hidden, setHidden] = useState<Set<string>>(new Set());
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const visible = promotions.filter((item) => !hidden.has(item.id));

  if (!visible.length) return <p className="text-sm text-neutral-400">Keine offenen Promotion-Anfragen.</p>;
  const decide = (id: string, status: "approved" | "rejected") => {
    setError(null);
    startTransition(async () => {
      try {
        await reviewPromotion(id, status, notes[id] ?? "");
        setHidden((current) => new Set(current).add(id));
      } catch (cause) { setError(cause instanceof Error ? cause.message : "Die Entscheidung konnte nicht gespeichert werden."); }
    });
  };

  return (
    <div>
      {error && <p className="mb-3 text-sm text-red-700">{error}</p>}
      <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white shadow-sm">
        <table className="w-full text-sm"><thead className="border-b border-black/[0.06] text-left"><tr><th className="type-label px-4 py-3">Event</th><th className="type-label px-4 py-3">Platzierung</th><th className="type-label px-4 py-3">Antragsteller</th><th className="type-label px-4 py-3">Begründung</th><th className="type-label px-4 py-3">Redaktionsnotiz</th><th className="px-4 py-3" /></tr></thead>
          <tbody className="divide-y divide-neutral-200">{visible.map((promotion) => <tr key={promotion.id} className="align-top hover:bg-neutral-50"><td className="px-4 py-3 font-medium text-neutral-900"><span className="block">{promotion.eventTitle}</span><span className="text-xs font-normal text-neutral-500">{formatDate(promotion.eventStart)}</span></td><td className="px-4 py-3 text-neutral-600">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</td><td className="px-4 py-3 text-neutral-600">{promotion.requester}</td><td className="max-w-[14rem] px-4 py-3 text-neutral-500">{promotion.requesterNote ?? "—"}</td><td className="px-4 py-3"><textarea value={notes[promotion.id] ?? ""} onChange={(event) => setNotes((current) => ({ ...current, [promotion.id]: event.target.value }))} maxLength={1000} rows={2} aria-label={`Notiz für ${promotion.eventTitle}`} className="w-48 rounded border border-neutral-200 px-2 py-1 text-xs" placeholder="Optional" /></td><td className="px-4 py-3"><div className="flex flex-col items-end gap-2"><button disabled={pending} onClick={() => decide(promotion.id, "approved")} className="text-sm font-medium text-emerald-700 hover:text-emerald-900 disabled:opacity-50">Freigeben</button><button disabled={pending} onClick={() => decide(promotion.id, "rejected")} className="text-sm font-medium text-red-700 hover:text-red-900 disabled:opacity-50">Ablehnen</button></div></td></tr>)}</tbody>
        </table>
      </div>
    </div>
  );
}
