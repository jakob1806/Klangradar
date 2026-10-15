import { createAdminClient } from "@/lib/supabase/admin";

// Kalender-Abo (webcal) der gemerkten Konzerte eines Kontos. Zugang allein
// über das geheime Token aus calendar_feeds (my_calendar_feed_token()).
export const dynamic = "force-dynamic";

type FavoriteRow = {
  events: {
    id: string;
    slug: string;
    title: string;
    start_datetime: string;
    duration_minutes: number | null;
    status: string;
    venues: { name: string; address_street?: string | null; address_city?: string | null } | null;
  } | null;
};

const esc = (value: string) => value.replace(/\\/g, "\\\\").replace(/;/g, "\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
const stamp = (date: Date) => date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
// RFC 5545: Zeilen > 75 Oktette falten.
const fold = (line: string) => line.match(/.{1,73}/g)?.join("\r\n ") ?? line;

export async function GET(_request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token: raw } = await params;
  const token = raw.replace(/\.ics$/, "");
  if (!/^[a-f0-9]{40,80}$/.test(token)) return new Response("Not found", { status: 404 });

  const db = createAdminClient();
  const { data: feed } = await db.from("calendar_feeds").select("user_id").eq("token", token).maybeSingle();
  if (!feed) return new Response("Not found", { status: 404 });

  const since = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
  const { data } = await db
    .from("favorites")
    .select("events!inner(id, slug, title, start_datetime, duration_minutes, status, venues(name, address_street, address_city))")
    .eq("user_id", feed.user_id)
    .gte("events.start_datetime", since)
    .returns<FavoriteRow[]>();

  const now = stamp(new Date());
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Klangradar//Gemerkte Konzerte//DE",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Klangradar – Meine Konzerte",
    "X-WR-TIMEZONE:Europe/Berlin",
    "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
    "X-PUBLISHED-TTL:PT6H",
  ];
  for (const row of data ?? []) {
    const event = row.events;
    if (!event) continue;
    const start = new Date(event.start_datetime);
    const end = new Date(start.getTime() + (event.duration_minutes ?? 120) * 60 * 1000);
    const location = [event.venues?.name, event.venues?.address_street, event.venues?.address_city].filter(Boolean).join(", ");
    lines.push(
      "BEGIN:VEVENT",
      `UID:${event.id}@klangradar.com`,
      `DTSTAMP:${now}`,
      `DTSTART:${stamp(start)}`,
      `DTEND:${stamp(end)}`,
      fold(`SUMMARY:${esc(event.status === "cancelled" ? `ABGESAGT: ${event.title}` : event.title)}`),
      ...(location ? [fold(`LOCATION:${esc(location)}`)] : []),
      `URL:de.klangradar.native://event/${event.slug}`,
      ...(event.status === "cancelled" ? ["STATUS:CANCELLED"] : []),
      "END:VEVENT",
    );
  }
  lines.push("END:VCALENDAR");
  return new Response(lines.join("\r\n") + "\r\n", {
    headers: { "Content-Type": "text/calendar; charset=utf-8", "Cache-Control": "private, max-age=900" },
  });
}
