import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { SeriesForm } from "./series-form";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";

export const dynamic = "force-dynamic";

type EventRow = { id: string; title: string; start_datetime: string; organizer_id: string };
type SeriesRow = { id: string; title: string; description_de: string | null; image_url: string | null; events: { id: string; title: string; start_datetime: string }[] | null };

export default async function SeriesPage() {
  const supabase = await createClient();
  const organizers = await getEventOrganizerOptions();
  const organizerIds = organizers.map((organizer) => organizer.id);
  const now = new Date().toISOString();
  const [{ data: eventData }, { data: seriesData, error }] = await Promise.all([
    organizerIds.length
      ? supabase
          .from("events")
          .select("id, title, start_datetime, organizer_id")
          .eq("status", "scheduled")
          .gt("start_datetime", now)
          .in("organizer_id", organizerIds)
          .order("start_datetime", { ascending: true })
          .returns<EventRow[]>()
      : Promise.resolve({ data: [] as EventRow[] }),
    supabase.from("event_series").select("id, title, description_de, image_url, events(id, title, start_datetime)").order("created_at", { ascending: false }).returns<SeriesRow[]>(),
  ]);
  const events = eventData ?? [];
  const series = seriesData ?? [];

  return (
    <div>
      <PageHeader eyebrow="Programm" title="Veranstaltungsserien" description="Verwalte wiederkehrende Konzerte und Aufführungen gemeinsam, ohne jeden Termin neu anzulegen." />
      <PageBody className="flex flex-col gap-10">
        <SeriesForm
          organizers={organizers}
          events={events.map((event) => ({ id: event.id, title: event.title, startLabel: formatMunichDateTime(event.start_datetime), organizerId: event.organizer_id }))}
        />

        <section className="flex flex-col gap-3">
          <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Meine Serien</h2>
          {error ? (
            <Card>
              <CardContent className="pt-5 text-sm text-amber-700">Die Serien sind nach der nächsten Datenbank-Aktualisierung verfügbar.</CardContent>
            </Card>
          ) : series.length === 0 ? (
            <Card>
              <CardContent className="pt-5 text-sm text-[#726c78]">Noch keine Serie angelegt.</CardContent>
            </Card>
          ) : (
            <div className="grid gap-3 sm:grid-cols-2">
              {series.map((item) => (
                <Card key={item.id} className="overflow-hidden">
                  {item.image_url && <img src={item.image_url} alt="" className="h-28 w-full object-cover" />}
                  <CardContent className="pt-5">
                    <h3 className="font-semibold text-[#15131a]">{item.title}</h3>
                    {item.description_de && <p className="mt-1 line-clamp-2 text-sm text-[#4a4550]">{item.description_de}</p>}
                    <p className="mt-3 text-xs font-medium text-[#726c78]">
                      {item.events?.length ?? 0} Termin{(item.events?.length ?? 0) === 1 ? "" : "e"}
                    </p>
                    {item.events?.slice(0, 3).map((event) => (
                      <Link key={event.id} href={`/veranstalter/events/${event.id}`} className="mt-2 block text-sm text-[#2D2A6E] hover:underline">
                        {event.title} · {formatMunichDateTime(event.start_datetime)}
                      </Link>
                    ))}
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </section>
      </PageBody>
    </div>
  );
}
