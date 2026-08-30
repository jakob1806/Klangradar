"use client";

import Image from "next/image";
import { useMemo, useState } from "react";

type EventOption = { id: string; title: string; startLabel: string; venueName: string | null; imageUrl: string | null; sourceLabel: string };

export function PromotionEventPicker({ events }: { events: EventOption[] }) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [showAll, setShowAll] = useState(false);
  const [query, setQuery] = useState("");
  const selected = events.find((event) => event.id === selectedId) ?? null;
  const visibleEvents = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("de-DE");
    const filtered = normalized ? events.filter((event) => `${event.title} ${event.venueName ?? ""} ${event.startLabel}`.toLocaleLowerCase("de-DE").includes(normalized)) : events;
    return showAll || normalized ? filtered : filtered.slice(0, 6);
  }, [events, query, showAll]);

  return <section>
    <input type="hidden" name="event_id" value={selectedId ?? ""} required />
    <div className="flex items-end justify-between gap-4"><div><h3 className="text-sm font-medium text-[#1d1d1f]">Event auswählen</h3><p className="mt-1 text-xs text-[#86868b]">Eigene Events und Termine deiner beanspruchten Profile.</p></div>{events.length > 6 && <button type="button" onClick={() => setShowAll((value) => !value)} className="shrink-0 text-sm font-medium text-[#0071e3] hover:underline">{showAll ? "Weniger zeigen" : `Alle ${events.length} zeigen`}</button>}</div>
    <div className="mt-3 grid gap-3 sm:grid-cols-2">{visibleEvents.map((event) => { const active = event.id === selectedId; return <button key={event.id} type="button" onClick={() => setSelectedId(event.id)} className={`flex overflow-hidden rounded-xl border text-left transition ${active ? "border-[#0071e3] bg-blue-50 ring-1 ring-[#0071e3]" : "border-black/10 bg-white hover:border-[#0071e3]"}`}><div className="relative m-3 h-16 w-20 shrink-0 overflow-hidden rounded-lg bg-[#f5f5f7]">{event.imageUrl && <Image src={event.imageUrl} alt="" fill sizes="80px" className="object-cover" unoptimized />}</div><span className="min-w-0 py-3 pr-3"><span className="line-clamp-2 block text-sm font-semibold text-[#1d1d1f]">{event.title}</span><span className="mt-1 block text-xs text-[#48484a]">{event.startLabel}{event.venueName ? ` · ${event.venueName}` : ""}</span><span className="mt-1 block truncate text-xs text-[#86868b]">{event.sourceLabel}</span></span></button>; })}</div>
    {events.length > 6 && <label className="mt-4 block text-sm font-medium text-[#1d1d1f]">Event filtern <span className="font-normal text-[#86868b]">(optional)</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Titel, Ort oder Datum" className="mt-1.5 w-full rounded-xl border border-black/10 bg-white px-3 py-2 text-sm outline-none focus:border-[#0071e3] focus:ring-1 focus:ring-[#0071e3]" /></label>}
    {selected && <p className="mt-3 text-sm font-medium text-[#0071e3]">Ausgewählt: {selected.title}</p>}
  </section>;
}
