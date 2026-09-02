"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { formatMunichDateTime } from "@/lib/munich-time";
import { Input } from "@/components/organizer/ui/input";
import { Badge } from "@/components/organizer/ui/badge";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/organizer/ui/table";

const STATUS_LABEL: Record<string, string> = {
  scheduled: "Geplant",
  sold_out: "Ausverkauft",
  cancelled: "Abgesagt",
  postponed: "Verschoben",
  draft: "Entwurf",
};

export interface ListedEventRow {
  id: string;
  title: string;
  start_datetime: string;
  status: string;
  venueName: string | null;
  imageUrl: string | null;
  source: "own" | "claimed";
  sourceLabel?: string;
}

// Nutzerfeedback: keine Suche, kein Status-Filter -- bei mehreren laufenden
// Reihen/Serien wird die Tabelle schnell unübersichtlich. Filtert
// client-seitig über die bereits geladenen Events, kein Zusatz-Request
// nötig (Veranstalter-Eventmengen sind klein genug dafür).
export function EventsTable({ events }: { events: ListedEventRow[] }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<string>("all");

  const statuses = useMemo(() => [...new Set(events.map((e) => e.status))], [events]);

  const filtered = events.filter((event) => {
    if (status !== "all" && event.status !== status) return false;
    if (query.trim()) {
      const q = query.trim().toLowerCase();
      if (!event.title.toLowerCase().includes(q) && !(event.venueName ?? "").toLowerCase().includes(q)) return false;
    }
    return true;
  });

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap gap-2">
        <Input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Titel oder Ort durchsuchen…"
          className="max-w-xs"
        />
        <select
          value={status}
          onChange={(e) => setStatus(e.target.value)}
          className="h-9 rounded-lg border border-black/10 bg-white px-3 text-sm text-[#15131a] focus-visible:border-[#2D2A6E] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2D2A6E]/25"
        >
          <option value="all">Alle Status</option>
          {statuses.map((s) => (
            <option key={s} value={s}>
              {STATUS_LABEL[s] ?? s}
            </option>
          ))}
        </select>
      </div>

      {filtered.length === 0 ? (
        <p className="py-6 text-sm text-[#726c78]">Keine Events für diese Suche/diesen Filter.</p>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Bild</TableHead>
              <TableHead>Titel</TableHead>
              <TableHead>Ort</TableHead>
              <TableHead>Termin</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Zuordnung</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.map((event) => (
              <TableRow key={event.id}>
                <TableCell>
                  <div className="relative h-12 w-16 overflow-hidden rounded-md bg-[#15131a]/[0.04]">
                    {event.imageUrl && <Image src={event.imageUrl} alt="" fill className="object-cover" sizes="64px" unoptimized />}
                  </div>
                </TableCell>
                <TableCell className="font-medium">{event.title}</TableCell>
                <TableCell className="text-[#4a4550]">{event.venueName ?? "—"}</TableCell>
                <TableCell className="tabular-nums text-[#4a4550]">{formatMunichDateTime(event.start_datetime)}</TableCell>
                <TableCell>
                  <Badge>{STATUS_LABEL[event.status] ?? event.status}</Badge>
                </TableCell>
                <TableCell className="text-xs text-[#726c78]" title={event.source === "claimed" ? "Termin eines beanspruchten Profils (Venue/Person/Ensemble), nicht selbst angelegt" : undefined}>
                  {event.source === "own" ? "Eigenes Event" : event.sourceLabel}
                </TableCell>
                <TableCell className="text-right">
                  {event.source === "own" ? (
                    <Link href={`/veranstalter/events/${event.id}`} className="font-semibold text-[#2D2A6E] hover:underline">
                      Bearbeiten
                    </Link>
                  ) : (
                    <Link href={`/veranstalter/events/discover/${event.id}`} className="font-semibold text-[#2D2A6E] hover:underline">
                      Ansehen
                    </Link>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
