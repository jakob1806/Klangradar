"use client";

import { useMemo, useState } from "react";

type EventOption = { id: string; title: string; startLabel: string };

export function PromotionEventPicker({ events }: { events: EventOption[] }) {
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<EventOption | null>(null);
  const matches = useMemo(() => events.filter((event) => `${event.title} ${event.startLabel}`.toLocaleLowerCase("de-DE").includes(query.toLocaleLowerCase("de-DE"))).slice(0, 8), [events, query]);
  return <div>
    <input type="hidden" name="event_id" value={selected?.id ?? ""} required />
    <label className="block text-sm font-medium text-[#1d1d1f]" htmlFor="promotion-event-search">Event</label>
    <input id="promotion-event-search" value={selected ? `${selected.title} · ${selected.startLabel}` : query} onChange={(event) => { setSelected(null); setQuery(event.target.value); }} placeholder="Event nach Titel oder Termin suchen …" className="mt-1.5 w-full rounded-lg border border-black/10 bg-white px-3 py-2 text-sm outline-none ring-[#0071e3] focus:ring-2" />
    {!selected && query && <div className="mt-2 overflow-hidden rounded-lg border border-black/10 bg-white shadow-sm">{matches.length ? matches.map((event) => <button type="button" key={event.id} onClick={() => { setSelected(event); setQuery(""); }} className="block w-full border-b border-black/[0.05] px-3 py-2.5 text-left text-sm last:border-0 hover:bg-[#f5f5f7]"><span className="block font-medium text-[#1d1d1f]">{event.title}</span><span className="text-xs text-[#86868b]">{event.startLabel}</span></button>) : <p className="px-3 py-3 text-sm text-[#86868b]">Kein passendes eigenes Event gefunden.</p>}</div>}
    {selected && <p className="mt-2 text-xs text-[#0071e3]">Ausgewählt. Nur kommende Events deiner bestätigten Institutionen sind verfügbar.</p>}
  </div>;
}
