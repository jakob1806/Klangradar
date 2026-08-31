import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Button } from "@/components/organizer/ui/button";

export const dynamic = "force-dynamic";

const PLACEMENT_LABEL: Record<string, string> = {
  standard: "Standard",
  featured: "Featured",
  local_spotlight: "Local Spotlight",
  homepage_feature: "Homepage Feature",
  push: "Push-Anfrage",
};

type EventMetric = { event_id: string; title: string; start_datetime: string; views: number; saves: number; shares: number; ticket_clicks: number };
type Promotion = { id: string; placement: string; status: string; payment_status: string; requested_at: string; events: { id: string; title: string; start_datetime: string } | null };

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardContent className="pt-5">
        <p className="text-xs font-medium text-[#726c78]">{label}</p>
        <p className="mt-1 text-2xl font-semibold tracking-tight text-[#15131a]">{value.toLocaleString("de-DE")}</p>
      </CardContent>
    </Card>
  );
}

function statusVariant(status: string): "success" | "warning" | "danger" | "default" {
  if (status === "approved") return "success";
  if (status === "payment_pending") return "warning";
  if (status === "rejected") return "danger";
  return "default";
}

function statusLabel(status: string) {
  return status === "approved" ? "Aktiv" : status === "payment_pending" ? "Zahlung ausstehend" : status === "rejected" ? "Abgelehnt" : "In Prüfung";
}

export default async function MarketingPage() {
  const supabase = await createClient();
  await getEventOrganizerOptions();
  const [{ data: promotionsData, error: promotionsError }, { data: metricsData, error: metricsError }] = await Promise.all([
    supabase.from("event_promotions").select("id, placement, status, payment_status, requested_at, events(id, title, start_datetime)").order("requested_at", { ascending: false }).returns<Promotion[]>(),
    supabase.rpc("organizer_event_metrics").returns<EventMetric[]>(),
  ]);
  const promotions = promotionsData ?? [];
  const metrics = Array.isArray(metricsData) ? metricsData : [];
  const metricByEvent = new Map(metrics.map((metric) => [metric.event_id, metric]));
  const active = promotions.filter((promotion) => promotion.status === "approved" && promotion.payment_status === "paid");
  const totals = metrics.reduce((sum, item) => ({ views: sum.views + Number(item.views), tickets: sum.tickets + Number(item.ticket_clicks), saves: sum.saves + Number(item.saves) }), { views: 0, tickets: 0, saves: 0 });

  return (
    <div>
      <PageHeader
        eyebrow="Sichtbarkeit"
        title="Marketing Center"
        description="Plane Sichtbarkeit und beobachte die Entwicklung deiner beworbenen Veranstaltungen."
        actions={
          <Button asChild>
            <Link href="/veranstalter/promote">Neue Kampagne</Link>
          </Button>
        }
      />
      <PageBody>
        {promotionsError || metricsError ? (
          <p className="text-sm text-[#8a5a0c]">Das Marketing Center ist nach der nächsten Datenbank-Aktualisierung verfügbar.</p>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <Metric label="Aktive Kampagnen" value={active.length} />
              <Metric label="Event-Aufrufe" value={totals.views} />
              <Metric label="Gespeichert" value={totals.saves} />
              <Metric label="Ticketlink-Klicks" value={totals.tickets} />
            </div>
            <p className="mt-3 text-xs leading-5 text-[#726c78]">
              Aufrufe, Saves und Ticket-Klicks zeigen aktuell die Gesamtentwicklung des jeweiligen Events, nicht nur Zugriffe aus einer einzelnen Kampagne. Kanalgenaue Reichweitenmessung wird als nächster Schritt ergänzt.
            </p>
            <section className="mt-10 flex flex-col gap-3">
              <div className="flex items-baseline justify-between gap-3">
                <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Kampagnen</h2>
                <Link href="/veranstalter/finanzen" className="text-sm font-semibold text-[#2D2A6E] hover:underline">
                  Kosten ansehen
                </Link>
              </div>
              {promotions.length === 0 ? (
                <Card>
                  <CardContent className="pt-5 text-sm text-[#726c78]">Noch keine Kampagnen angelegt.</CardContent>
                </Card>
              ) : (
                <div className="grid gap-3">
                  {promotions.map((promotion) => {
                    const metric = promotion.events ? metricByEvent.get(promotion.events.id) : undefined;
                    return (
                      <Card key={promotion.id}>
                        <CardContent className="flex flex-wrap items-start justify-between gap-3 pt-5">
                          <div>
                            <p className="font-semibold text-[#15131a]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</p>
                            <p className="mt-1 text-sm text-[#4a4550]">{promotion.events?.title ?? "Gelöschtes Event"}</p>
                            <p className="mt-1 text-xs text-[#726c78]">{promotion.events && formatMunichDateTime(promotion.events.start_datetime)}</p>
                          </div>
                          <Badge variant={statusVariant(promotion.status)}>{statusLabel(promotion.status)}</Badge>
                        </CardContent>
                        <CardContent className="flex flex-wrap gap-x-6 gap-y-2 pt-0 text-sm text-[#4a4550]">
                          <span><strong className="text-[#15131a]">{metric?.views ?? 0}</strong> Aufrufe</span>
                          <span><strong className="text-[#15131a]">{metric?.ticket_clicks ?? 0}</strong> Ticket-Klicks</span>
                          <span><strong className="text-[#15131a]">{metric?.saves ?? 0}</strong> Saves</span>
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              )}
            </section>
          </>
        )}
      </PageBody>
    </div>
  );
}
