"use client";

import Image from "next/image";
import { useMemo, useState } from "react";
import { Input } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { Button } from "@/components/organizer/ui/button";

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

  return (
    <section>
      <input type="hidden" name="event_id" value={selectedId ?? ""} required />
      <div className="flex items-end justify-between gap-4">
        <div>
          <h3 className="text-sm font-medium text-[#15131a]">Event auswählen</h3>
          <p className="mt-1 text-xs text-[#726c78]">Eigene Events und Termine deiner beanspruchten Profile.</p>
        </div>
        {events.length > 6 && (
          <Button type="button" variant="link" size="sm" className="h-auto shrink-0 p-0" onClick={() => setShowAll((value) => !value)}>
            {showAll ? "Weniger zeigen" : `Alle ${events.length} zeigen`}
          </Button>
        )}
      </div>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        {visibleEvents.map((event) => {
          const active = event.id === selectedId;
          return (
            <button
              key={event.id}
              type="button"
              onClick={() => setSelectedId(event.id)}
              className={`flex overflow-hidden rounded-xl border text-left transition ${active ? "border-[#2D2A6E] bg-[#2D2A6E]/[0.04] ring-1 ring-[#2D2A6E]" : "border-[#15131a]/10 bg-white hover:border-[#2D2A6E]"}`}
            >
              <div className="relative m-3 h-16 w-20 shrink-0 overflow-hidden rounded-lg bg-[#15131a]/[0.04]">
                {event.imageUrl && <Image src={event.imageUrl} alt="" fill sizes="80px" className="object-cover" unoptimized />}
              </div>
              <span className="min-w-0 py-3 pr-3">
                <span className="line-clamp-2 block text-sm font-semibold text-[#15131a]">{event.title}</span>
                <span className="mt-1 block text-xs text-[#4a4550]">
                  {event.startLabel}
                  {event.venueName ? ` · ${event.venueName}` : ""}
                </span>
                <span className="mt-1 block truncate text-xs text-[#726c78]">{event.sourceLabel}</span>
              </span>
            </button>
          );
        })}
      </div>
      {events.length > 6 && (
        <div className="mt-4">
          <Label htmlFor="promotion-event-filter">
            Event filtern <span className="font-normal text-[#726c78]">(optional)</span>
          </Label>
          <Input
            id="promotion-event-filter"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Titel, Ort oder Datum"
            className="mt-1.5"
          />
        </div>
      )}
      {selected && <p className="mt-3 text-sm font-medium text-[#2D2A6E]">Ausgewählt: {selected.title}</p>}
    </section>
  );
}
