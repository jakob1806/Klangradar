import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (29.10.2026): CSV-Export der Veranstalter-
// Analytics (nur Summen pro eigenem Event, wie auf der Seite).
type Metric = { event_id: string; title: string; start_datetime: string; views: number; saves: number; ticket_clicks: number };

function cell(value: string | number) {
  const text = String(value);
  return /[";\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export async function GET() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new NextResponse("Nicht angemeldet", { status: 401 });
  const { data, error } = await supabase.rpc("organizer_event_metrics");
  if (error) return new NextResponse("Export nicht verfügbar", { status: 500 });
  const rows = (Array.isArray(data) ? data : []) as Metric[];
  const date = new Intl.DateTimeFormat("de-DE", { dateStyle: "short", timeStyle: "short", timeZone: "Europe/Berlin" });
  const lines = [
    ["Event", "Beginn", "Aufrufe", "Gemerkt", "Ticket-Klicks", "Conversion %"].join(";"),
    ...rows.map((row) =>
      [
        cell(row.title),
        cell(date.format(new Date(row.start_datetime))),
        Number(row.views),
        Number(row.saves),
        Number(row.ticket_clicks),
        Number(row.views) > 0 ? ((Number(row.ticket_clicks) / Number(row.views)) * 100).toFixed(1).replace(".", ",") : "",
      ].join(";"),
    ),
  ];
  // BOM, damit Excel Umlaute korrekt liest; Semikolon als deutsches Trennzeichen.
  return new NextResponse(`﻿${lines.join("\r\n")}\r\n`, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="klangradar-analytics-${new Date().toISOString().slice(0, 10)}.csv"`,
      "Cache-Control": "no-store",
    },
  });
}
