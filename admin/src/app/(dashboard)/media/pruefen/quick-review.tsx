"use client";

import { useCallback, useEffect, useState, useTransition } from "react";
import { decideImage } from "./actions";

export interface QueueItem {
  kind: "license" | "flag" | "report";
  image_id: string | null;
  flag_id: string | null;
  report_id: string | null;
  entity_type: string;
  entity_id: string;
  entity_name: string;
  upcoming: number | null;
  image_url: string;
  source_page_url: string | null;
  source_name: string | null;
  credits: string | null;
  license_status: string | null;
  license_name: string | null;
  reason: string;
}

const KIND_LABEL: Record<QueueItem["kind"], string> = {
  license: "Lizenz prüfen",
  flag: "Mögliche Fehlzuordnung",
  report: "In der App gemeldet",
};

const ENTITY_ROUTE: Record<string, string> = { person: "/persons", ensemble: "/ensembles", venue: "/venues", event: "/events" };

export function QuickReview({ items }: { items: QueueItem[] }) {
  const [queue, setQueue] = useState(items);
  const [index, setIndex] = useState(0);
  const [done, setDone] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const item = queue[index];

  const decide = useCallback((keep: boolean) => {
    if (!item || pending) return;
    setError(null);
    startTransition(async () => {
      try {
        await decideImage({
          kind: item.kind, imageId: item.image_id, flagId: item.flag_id, reportId: item.report_id,
          entityType: item.entity_type, entityId: item.entity_id, imageUrl: item.image_url,
          free: /^(cc|pd|public domain|gemeinfrei)/i.test(item.license_name ?? "") || item.license_status === "confirmed_free",
        }, keep);
        setQueue((q) => q.filter((_, i) => i !== index));
        setIndex((i) => Math.min(i, queue.length - 2));
        setDone((d) => d + 1);
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      }
    });
  }, [item, pending, index, queue.length]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) return;
      if (event.key === "j" || event.key === "J") decide(true);
      else if (event.key === "n" || event.key === "N") decide(false);
      else if (event.key === "ArrowRight") setIndex((i) => Math.min(i + 1, queue.length - 1));
      else if (event.key === "ArrowLeft") setIndex((i) => Math.max(i - 1, 0));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [decide, queue.length]);

  if (!item) {
    return (
      <div className="mt-8 rounded-xl border border-black/[0.06] bg-white p-8 text-center shadow-sm">
        <p className="text-lg font-semibold text-neutral-900">Alles geprüft</p>
        <p className="mt-1 text-sm text-neutral-500">{done > 0 ? `${done} Entscheidungen in dieser Sitzung.` : "Gerade wartet nichts auf eine Entscheidung."}</p>
      </div>
    );
  }

  const isLicense = item.kind === "license";
  return (
    <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
      <div className="flex min-h-[420px] items-center justify-center overflow-hidden rounded-xl border border-black/[0.06] bg-neutral-100">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={item.image_url} alt={item.entity_name} className="max-h-[70vh] w-auto object-contain" />
      </div>
      <aside className="flex flex-col gap-4 rounded-xl border border-black/[0.06] bg-white p-5 shadow-sm">
        <div className="flex items-center justify-between text-xs text-neutral-500">
          <span>{index + 1} von {queue.length}</span>
          <span>{done} erledigt</span>
        </div>
        <span className={`w-fit rounded-full px-2.5 py-1 text-xs font-medium ${item.kind === "license" ? "bg-sky-50 text-sky-800" : "bg-amber-50 text-amber-800"}`}>
          {KIND_LABEL[item.kind]}
        </span>
        <div>
          <a href={`${ENTITY_ROUTE[item.entity_type] ?? ""}/${item.entity_id}`} className="text-xl font-semibold text-neutral-900 hover:underline">
            {item.entity_name}
          </a>
          <p className="text-sm text-neutral-500">
            {item.entity_type === "event" ? "Konzert" : `${item.upcoming ?? 0} kommende Konzerte`}
          </p>
        </div>
        <p className="text-sm text-neutral-700">{item.reason}</p>
        <dl className="grid grid-cols-[90px_1fr] gap-x-3 gap-y-1.5 text-xs">
          <dt className="text-neutral-500">Quelle</dt>
          <dd className="break-all text-neutral-800">
            {item.source_page_url ? <a href={item.source_page_url} target="_blank" rel="noreferrer" className="hover:underline">{item.source_name ?? item.source_page_url}</a> : (item.source_name ?? "–")}
          </dd>
          <dt className="text-neutral-500">Credit</dt>
          <dd className="text-neutral-800">{item.credits ?? "–"}</dd>
          <dt className="text-neutral-500">Lizenz</dt>
          <dd className="text-neutral-800">{item.license_name ?? item.license_status ?? "–"}</dd>
        </dl>
        {error && <p className="text-xs text-red-700">{error}</p>}
        <div className="mt-auto grid grid-cols-2 gap-2">
          <button
            type="button"
            disabled={pending}
            onClick={() => decide(false)}
            className="rounded-lg border border-red-200 px-3 py-2.5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-50"
          >
            {isLicense ? "Verwerfen" : "Bild entfernen"} <kbd className="ml-1 text-xs opacity-60">N</kbd>
          </button>
          <button
            type="button"
            disabled={pending}
            onClick={() => decide(true)}
            className="rounded-lg bg-[#2D2A6E] px-3 py-2.5 text-sm font-medium text-white hover:opacity-90 disabled:opacity-50"
          >
            {isLicense ? "Übernehmen" : "Bild stimmt"} <kbd className="ml-1 text-xs opacity-70">J</kbd>
          </button>
        </div>
      </aside>
    </div>
  );
}
