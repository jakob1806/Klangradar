import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Button } from "@/components/organizer/ui/button";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/organizer/ui/table";

export const dynamic = "force-dynamic";

type Metric = { event_id: string; title: string; start_datetime: string; views: number; saves: number; shares: number; ticket_clicks: number };

function MetricCard({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardContent className="pt-5">
        <p className="text-sm text-[#6B6B6B]">{label}</p>
        <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{value.toLocaleString("de-DE")}</p>
      </CardContent>
    </Card>
  );
}

// Erstellt von Claude Code (29.10.2026): Weg von Aufruf über Merken zum
// Ticket-Klick als Trichter und Saisonübersicht nach Monat.
function FunnelStep({ label, value, base, note }: { label: string; value: number; base: number; note?: string }) {
  const width = base > 0 ? Math.max(2, Math.round((value / base) * 100)) : 0;
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-baseline justify-between gap-3 text-sm">
        <span className="font-medium text-[#111111]">{label}</span>
        <span className="tabular-nums text-[#6B6B6B]">
          {value.toLocaleString("de-DE")}
          {note ? <span className="ml-2 text-xs">{note}</span> : null}
        </span>
      </div>
      <div className="h-2.5 overflow-hidden rounded-full bg-[#F3F3F3]">
        <div className="h-full rounded-full bg-[#2D2A6E]" style={{ width: `${width}%` }} />
      </div>
    </div>
  );
}

const monthFormat = new Intl.DateTimeFormat("de-DE", { month: "long", year: "numeric", timeZone: "Europe/Berlin" });

function percentage(numerator: number, denominator: number) {
  if (denominator === 0) return "—";
  return new Intl.NumberFormat("de-DE", { style: "percent", maximumFractionDigits: 1 }).format(numerator / denominator);
}

export default async function AnalyticsPage() {
  const supabase = await createClient();
  await getEventOrganizerOptions();
  const { data, error } = await supabase.rpc("organizer_event_metrics").returns<Metric[]>();
  const metrics: Metric[] = Array.isArray(data) ? data : [];
  const totals = metrics.reduce((sum, item) => ({ views: sum.views + Number(item.views), saves: sum.saves + Number(item.saves), shares: sum.shares + Number(item.shares), ticketClicks: sum.ticketClicks + Number(item.ticket_clicks) }), { views: 0, saves: 0, shares: 0, ticketClicks: 0 });
  const conversion = percentage(totals.ticketClicks, totals.views);
  const monthKey = new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", timeZone: "Europe/Berlin" });
  const months = [...metrics.reduce((map, item) => {
    const key = monthKey.format(new Date(item.start_datetime));
    const entry = map.get(key) ?? { label: monthFormat.format(new Date(item.start_datetime)), events: 0, views: 0, saves: 0, ticketClicks: 0 };
    entry.events += 1;
    entry.views += Number(item.views);
    entry.saves += Number(item.saves);
    entry.ticketClicks += Number(item.ticket_clicks);
    return map.set(key, entry);
  }, new Map<string, { label: string; events: number; views: number; saves: number; ticketClicks: number }>())]
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([, value]) => value);

  return (
    <div>
      <PageHeader
        eyebrow="Kennzahlen"
        title="Analytics"
        description="Aggregierte Kennzahlen deiner Veranstaltungen. Persönliche Daten einzelner Besucher werden nicht angezeigt."
        actions={
          <>
            <Button asChild variant="outline">
              <a href="/veranstalter/analytics/export" download>
                CSV exportieren
              </a>
            </Button>
            <Button asChild>
              <Link href="/veranstalter/promote">Promotion planen</Link>
            </Button>
          </>
        }
      />
      <PageBody>
        {error ? (
          <p className="text-sm text-[#8a5a0c]">Die Analytics sind nach der nächsten Datenbank-Aktualisierung verfügbar.</p>
        ) : (
          <>
            {/* Nutzerfeedback: "Shares" wird bislang von keiner App-Version
                geschrieben und stand deshalb immer bei 0 -- las sich wie ein
                echtes, aber schlechtes Ergebnis statt wie fehlende Daten.
                Karte entfernt, Spalte unten bleibt mit Hinweis statt
                irreführender Null. */}
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <MetricCard label="Event-Aufrufe" value={totals.views} />
              <MetricCard label="Gespeichert" value={totals.saves} />
              <MetricCard label="Ticketlink-Klicks" value={totals.ticketClicks} />
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#6B6B6B]">Ticket-Conversion</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{conversion}</p>
                  <p className="mt-1 text-xs text-[#6B6B6B]">Ticket-Klicks / Aufrufe</p>
                </CardContent>
              </Card>
            </div>
            {totals.views > 0 && (
              <div className="mt-6 grid gap-3 lg:grid-cols-2">
                <Card>
                  <CardContent className="flex flex-col gap-4 pt-5">
                    <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">Vom Aufruf zum Ticket</h2>
                    <FunnelStep label="Event aufgerufen" value={totals.views} base={totals.views} />
                    <FunnelStep label="Gemerkt" value={totals.saves} base={totals.views} note={percentage(totals.saves, totals.views)} />
                    <FunnelStep label="Ticketlink geklickt" value={totals.ticketClicks} base={totals.views} note={percentage(totals.ticketClicks, totals.views)} />
                  </CardContent>
                </Card>
                <Card>
                  <CardContent className="flex flex-col gap-3 pt-5">
                    <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">Saison nach Monat</h2>
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Monat</TableHead>
                          <TableHead>Events</TableHead>
                          <TableHead>Aufrufe</TableHead>
                          <TableHead>Gemerkt</TableHead>
                          <TableHead>Tickets</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {months.slice(0, 12).map((month) => (
                          <TableRow key={month.label}>
                            <TableCell className="whitespace-nowrap">{month.label}</TableCell>
                            <TableCell className="tabular-nums">{month.events}</TableCell>
                            <TableCell className="tabular-nums">{month.views.toLocaleString("de-DE")}</TableCell>
                            <TableCell className="tabular-nums">{month.saves.toLocaleString("de-DE")}</TableCell>
                            <TableCell className="tabular-nums">{month.ticketClicks.toLocaleString("de-DE")}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>
              </div>
            )}
            <section className="mt-10 flex flex-col gap-3">
              <div className="flex items-baseline justify-between">
                <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">Nach Veranstaltung</h2>
                {metrics.length > 0 && <p className="text-xs text-[#6B6B6B]">* Shares werden aktuell noch nicht erfasst.</p>}
              </div>
              {metrics.length === 0 ? (
                <Card>
                  <CardContent className="pt-5 text-sm text-[#6B6B6B]">Sobald deine Events aufgerufen werden, erscheinen die Kennzahlen hier.</CardContent>
                </Card>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Event</TableHead>
                      <TableHead>Aufrufe</TableHead>
                      <TableHead>Saves</TableHead>
                      <TableHead title="Wird noch von keiner Klangradar-App-Version erfasst">Shares*</TableHead>
                      <TableHead>Tickets</TableHead>
                      <TableHead>Conversion</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {metrics.map((item) => (
                      <TableRow key={item.event_id}>
                        <TableCell>
                          <Link className="font-medium text-[#111111] hover:text-[#2D2A6E]" href={`/veranstalter/events/${item.event_id}`}>
                            {item.title}
                          </Link>
                          <span className="mt-0.5 block text-xs text-[#6B6B6B]">{formatMunichDateTime(item.start_datetime)}</span>
                        </TableCell>
                        <TableCell className="tabular-nums">{item.views}</TableCell>
                        <TableCell className="tabular-nums">{item.saves}</TableCell>
                        <TableCell className="tabular-nums text-[#8A8A8A]">–</TableCell>
                        <TableCell className="tabular-nums">{item.ticket_clicks}</TableCell>
                        <TableCell className="tabular-nums">{percentage(item.ticket_clicks, item.views)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </section>
          </>
        )}
      </PageBody>
    </div>
  );
}
