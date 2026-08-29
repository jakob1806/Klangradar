import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { SeriesForm } from "./series-form";

export const dynamic = "force-dynamic";

type EventRow = { id: string; title: string; start_datetime: string; organizer_id: string };
type SeriesRow = { id: string; title: string; description_de: string | null; image_url: string | null; events: { id: string; title: string; start_datetime: string }[] | null };

export default async function SeriesPage() {
  const supabase = await createClient();
  const organizers = await getEventOrganizerOptions();
  const organizerIds = organizers.map((organizer) => organizer.id);
  const now = new Date().toISOString();
  const [{ data: eventData }, { data: seriesData, error }] = await Promise.all([
    organizerIds.length ? supabase.from("events").select("id, title, start_datetime, organizer_id").eq("status", "scheduled").gt("start_datetime", now).in("organizer_id", organizerIds).order("start_datetime", { ascending: true }).returns<EventRow[]>() : Promise.resolve({ data: [] as EventRow[] }),
    supabase.from("event_series").select("id, title, description_de, image_url, events(id, title, start_datetime)").order("created_at", { ascending: false }).returns<SeriesRow[]>(),
  ]);
  const events = eventData ?? [];
  const series = seriesData ?? [];

  return <div className="mx-auto max-w-5xl px-6 py-10"><div><h1 className="type-heading text-2xl text-[#1d1d1f]">Veranstaltungsserien</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Verwalte wiederkehrende Konzerte und Aufführungen gemeinsam, ohne jeden Termin neu anzulegen.</p></div>
    <div className="mt-8"><SeriesForm organizers={organizers} events={events.map((event) => ({ id: event.id, title: event.title, startLabel: formatMunichDateTime(event.start_datetime), organizerId: event.organizer_id }))} /></div>
    <section className="mt-10"><h2 className="text-lg font-semibold text-[#1d1d1f]">Meine Serien</h2>{error ? <p className="mt-3 text-sm text-amber-700">Die Serien sind nach der nächsten Datenbank-Aktualisierung verfügbar.</p> : series.length === 0 ? <p className="mt-3 text-sm text-[#86868b]">Noch keine Serie angelegt.</p> : <div className="mt-3 grid gap-3 sm:grid-cols-2">{series.map((item) => <article key={item.id} className="overflow-hidden rounded-2xl border border-black/[.06] bg-white">{item.image_url && <img src={item.image_url} alt="" className="h-28 w-full object-cover" />}<div className="p-4"><h3 className="font-semibold text-[#1d1d1f]">{item.title}</h3>{item.description_de && <p className="mt-1 line-clamp-2 text-sm text-[#48484a]">{item.description_de}</p>}<p className="mt-3 text-xs font-medium text-[#86868b]">{item.events?.length ?? 0} Termin{(item.events?.length ?? 0) === 1 ? "" : "e"}</p>{item.events?.slice(0, 3).map((event) => <Link key={event.id} href={`/veranstalter/events/${event.id}`} className="mt-2 block text-sm text-[#0071e3] hover:underline">{event.title} · {formatMunichDateTime(event.start_datetime)}</Link>)}</div></article>)}</div>}</section>
  </div>;
}
