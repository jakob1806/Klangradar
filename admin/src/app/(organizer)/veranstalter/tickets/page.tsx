import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Input } from "@/components/organizer/ui/input";
import { SubmitButton } from "@/components/organizer/submit-button";
import { ActionForm } from "@/components/organizer/action-form";
import { saveTicketDetails } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): In den Quellen fehlen
// Ticket-Links fast immer. Hier tragen Veranstalter Link und Preise für alle
// kommenden Termine in einer Liste nach, ohne jedes Event einzeln zu öffnen.

interface TicketEvent {
  id: string;
  title: string;
  start_datetime: string;
  ticket_url: string | null;
  price_min: number | null;
  price_max: number | null;
  is_free: boolean;
  venues: { name: string } | null;
}

function hasPrice(event: TicketEvent) {
  return event.is_free || event.price_min !== null;
}

export default async function TicketGapsPage({ searchParams }: { searchParams: Promise<{ show?: string }> }) {
  const { show } = await searchParams;
  const supabase = await createClient();
  const organizers = await getEventOrganizerOptions();
  const ids = organizers.map((organizer) => organizer.id);
  const { data } = ids.length
    ? await supabase
        .from("events")
        .select("id, title, start_datetime, ticket_url, price_min, price_max, is_free, venues(name)")
        .in("organizer_id", ids)
        .gte("start_datetime", new Date().toISOString())
        .in("status", ["scheduled", "sold_out"])
        .order("start_datetime")
        .limit(300)
        .returns<TicketEvent[]>()
    : { data: [] as TicketEvent[] };
  const events = data ?? [];
  const incomplete = events.filter((event) => !event.ticket_url || !hasPrice(event));
  const listed = show === "all" ? events : incomplete;
  const withLink = events.filter((event) => event.ticket_url).length;

  return (
    <div>
      <PageHeader
        eyebrow="Programm"
        title="Tickets & Preise"
        description="Mit Ticket-Link führt die App direkt zum Kauf, mit Preis lässt sich besser filtern. Hier tragt ihr beides für alle kommenden Termine in einer Liste nach."
      />
      <PageBody>
        <div className="grid gap-3 sm:grid-cols-3">
          <Card>
            <CardContent className="pt-5">
              <p className="text-sm text-[#6B6B6B]">Kommende Termine</p>
              <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{events.length}</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-5">
              <p className="text-sm text-[#6B6B6B]">Mit Ticket-Link</p>
              <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{withLink}</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-5">
              <p className="text-sm text-[#6B6B6B]">Unvollständig</p>
              <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{incomplete.length}</p>
            </CardContent>
          </Card>
        </div>

        <div className="mt-8 flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">{show === "all" ? "Alle Termine" : "Unvollständig"}</h2>
          <div className="flex gap-1 rounded-lg bg-[#F3F3F3] p-1 text-[13px] font-medium">
            <Link href="/veranstalter/tickets" aria-current={show !== "all" ? "page" : undefined} className={`rounded-md px-3 py-1 ${show !== "all" ? "bg-white text-[#111111] shadow-sm" : "text-[#6B6B6B]"}`}>
              Unvollständig ({incomplete.length})
            </Link>
            <Link href="/veranstalter/tickets?show=all" aria-current={show === "all" ? "page" : undefined} className={`rounded-md px-3 py-1 ${show === "all" ? "bg-white text-[#111111] shadow-sm" : "text-[#6B6B6B]"}`}>
              Alle ({events.length})
            </Link>
          </div>
        </div>

        {listed.length === 0 ? (
          <Card className="mt-3">
            <CardContent className="pt-5 text-sm text-[#6B6B6B]">
              {events.length === 0 ? "Ihr habt keine kommenden Termine." : "Alle kommenden Termine haben Ticket-Link und Preis."}
            </CardContent>
          </Card>
        ) : (
          <div className="mt-3 flex flex-col gap-3">
            {listed.map((event) => (
              <Card key={event.id}>
                <CardContent className="flex flex-col gap-3 pt-5">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div className="min-w-0">
                      <Link href={`/veranstalter/events/${event.id}`} className="font-medium text-[#111111] hover:text-[#2D2A6E]">
                        {event.title}
                      </Link>
                      <p className="text-[13px] text-[#6B6B6B]">
                        {formatMunichDateTime(event.start_datetime)}
                        {event.venues?.name ? ` · ${event.venues.name}` : ""}
                      </p>
                    </div>
                    <div className="flex gap-1.5">
                      {!event.ticket_url && <Badge variant="warning">Ticket-Link fehlt</Badge>}
                      {!hasPrice(event) && <Badge variant="warning">Preis fehlt</Badge>}
                    </div>
                  </div>
                  <ActionForm action={saveTicketDetails.bind(null, event.id)} className="flex flex-wrap items-center gap-2">
                    <Input name="ticket_url" type="url" aria-label="Ticket-Link" placeholder="Ticket-Link https://…" defaultValue={event.ticket_url ?? ""} className="min-w-56 flex-[2]" />
                    <Input name="price_min" inputMode="decimal" aria-label="Preis ab (€)" placeholder="ab €" defaultValue={event.price_min ?? ""} className="w-24" />
                    <Input name="price_max" inputMode="decimal" aria-label="Preis bis (€)" placeholder="bis €" defaultValue={event.price_max ?? ""} className="w-24" />
                    <label className="flex items-center gap-2 text-[13px] text-[#4A4A4A]">
                      <input type="checkbox" name="is_free" defaultChecked={event.is_free} className="size-4 accent-[#2D2A6E]" />
                      Eintritt frei
                    </label>
                    <SubmitButton size="sm">Speichern</SubmitButton>
                  </ActionForm>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </PageBody>
    </div>
  );
}
