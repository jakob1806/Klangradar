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
        <p className="text-sm text-[#726c78]">{label}</p>
        <p className="mt-1 text-3xl font-semibold tracking-tight text-[#15131a]">{value.toLocaleString("de-DE")}</p>
      </CardContent>
    </Card>
  );
}

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

  return (
    <div>
      <PageHeader
        eyebrow="Kennzahlen"
        title="Analytics"
        description="Aggregierte Kennzahlen deiner Veranstaltungen. Persönliche Daten einzelner Besucher werden nicht angezeigt."
        actions={
          <Button asChild>
            <Link href="/veranstalter/promote">Promotion planen</Link>
          </Button>
        }
      />
      <PageBody>
        {error ? (
          <p className="text-sm text-[#8a5a0c]">Die Analytics sind nach der nächsten Datenbank-Aktualisierung verfügbar.</p>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
              <MetricCard label="Event-Aufrufe" value={totals.views} />
              <MetricCard label="Gespeichert" value={totals.saves} />
              <MetricCard label="Geteilt" value={totals.shares} />
              <MetricCard label="Ticketlink-Klicks" value={totals.ticketClicks} />
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#726c78]">Ticket-Conversion</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#15131a]">{conversion}</p>
                  <p className="mt-1 text-xs text-[#726c78]">Ticket-Klicks / Aufrufe</p>
                </CardContent>
              </Card>
            </div>
            <section className="mt-10 flex flex-col gap-3">
              <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Nach Veranstaltung</h2>
              {metrics.length === 0 ? (
                <Card>
                  <CardContent className="pt-5 text-sm text-[#726c78]">Sobald deine Events aufgerufen werden, erscheinen die Kennzahlen hier.</CardContent>
                </Card>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Event</TableHead>
                      <TableHead>Aufrufe</TableHead>
                      <TableHead>Saves</TableHead>
                      <TableHead>Shares</TableHead>
                      <TableHead>Tickets</TableHead>
                      <TableHead>Conversion</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {metrics.map((item) => (
                      <TableRow key={item.event_id}>
                        <TableCell>
                          <Link className="font-medium text-[#15131a] hover:text-[#2D2A6E]" href={`/veranstalter/events/${item.event_id}`}>
                            {item.title}
                          </Link>
                          <span className="mt-0.5 block text-xs text-[#726c78]">{formatMunichDateTime(item.start_datetime)}</span>
                        </TableCell>
                        <TableCell className="tabular-nums">{item.views}</TableCell>
                        <TableCell className="tabular-nums">{item.saves}</TableCell>
                        <TableCell className="tabular-nums">{item.shares}</TableCell>
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
