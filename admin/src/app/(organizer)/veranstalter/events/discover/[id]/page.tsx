import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";

export const dynamic = "force-dynamic";

type EventRow = {
  id: string;
  title: string;
  subtitle: string | null;
  description_de: string | null;
  start_datetime: string;
  duration_minutes: number | null;
  doors_info: string | null;
  ticket_url: string | null;
  is_free: boolean;
  price_min: number | null;
  price_max: number | null;
  image_urls: string[] | null;
  venues: { name: string; address_street: string; address_zip: string; address_city: string } | null;
};

type Participant = {
  id: string;
  role: string | null;
  display_order: number;
  persons: { full_name: string } | null;
  ensembles: { name: string } | null;
};

type Work = {
  position: number;
  after_intermission: boolean;
  works: { title: string; composer: { full_name: string } | null } | null;
};

function priceLabel(event: EventRow) {
  if (event.is_free) return "Eintritt frei";
  if (event.price_min === null && event.price_max === null) return null;
  const format = (price: number) => new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(price);
  return event.price_min !== null && event.price_max !== null && event.price_min !== event.price_max
    ? `${format(event.price_min)} – ${format(event.price_max)}`
    : format(event.price_min ?? event.price_max!);
}

export default async function OrganizerDiscoverEventDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const now = new Date().toISOString();
  const [{ data: event }, { data: participants }, { data: works }] = await Promise.all([
    supabase.from("events").select("id, title, subtitle, description_de, start_datetime, duration_minutes, doors_info, ticket_url, is_free, price_min, price_max, image_urls, venues(name, address_street, address_zip, address_city)").eq("id", id).eq("status", "scheduled").gte("start_datetime", now).maybeSingle<EventRow>(),
    supabase.from("event_participants").select("id, role, display_order, persons(full_name), ensembles(name)").eq("event_id", id).order("display_order", { ascending: true }).returns<Participant[]>(),
    supabase.from("event_works").select("position, after_intermission, works(title, composer:persons(full_name))").eq("event_id", id).order("position", { ascending: true }).returns<Work[]>(),
  ]);

  if (!event) notFound();
  const price = priceLabel(event);

  return <div className="mx-auto max-w-4xl px-6 py-10">
    <Link href="/veranstalter/events/discover" className="text-sm font-medium text-[#0071e3] hover:underline">← Alle Events</Link>
    <div className="mt-5 overflow-hidden rounded-2xl border border-black/[0.06] bg-white">
      <div className="relative aspect-[16/8] bg-[#f5f5f7]">
        {event.image_urls?.[0] ? <Image src={event.image_urls[0]} alt="" fill priority className="object-cover" sizes="(max-width: 896px) 100vw, 896px" unoptimized /> : <div className="flex h-full items-end bg-gradient-to-br from-[#e8efff] to-[#f5f5f7] p-8"><span className="text-sm font-medium text-[#48484a]">Klangradar</span></div>}
      </div>
      <div className="p-6 sm:p-9">
        <p className="text-sm font-semibold text-[#0071e3]">{formatMunichDateTime(event.start_datetime)}</p>
        <h1 className="type-heading mt-3 text-3xl text-[#1d1d1f] sm:text-4xl">{event.title}</h1>
        {event.subtitle && <p className="mt-3 text-lg text-[#48484a]">{event.subtitle}</p>}
        <div className="mt-7 grid gap-5 border-y border-black/[0.06] py-6 sm:grid-cols-2">
          <div><p className="text-xs font-semibold uppercase tracking-wide text-[#86868b]">Ort</p><p className="mt-1 font-medium text-[#1d1d1f]">{event.venues?.name ?? "Ort wird noch bekanntgegeben"}</p>{event.venues && <p className="text-sm text-[#48484a]">{event.venues.address_street}, {event.venues.address_zip} {event.venues.address_city}</p>}</div>
          <div><p className="text-xs font-semibold uppercase tracking-wide text-[#86868b]">Eintritt</p><p className="mt-1 font-medium text-[#1d1d1f]">{price ?? "Preisinformation folgt"}</p>{event.doors_info && <p className="text-sm text-[#48484a]">{event.doors_info}</p>}</div>
        </div>
        {event.description_de && <section className="mt-8"><h2 className="text-lg font-semibold text-[#1d1d1f]">Über das Event</h2><p className="mt-3 whitespace-pre-wrap leading-7 text-[#48484a]">{event.description_de}</p></section>}
        {(participants ?? []).length > 0 && <section className="mt-8"><h2 className="text-lg font-semibold text-[#1d1d1f]">Mitwirkende</h2><div className="mt-3 flex flex-wrap gap-2">{participants!.map((participant) => <span key={participant.id} className="rounded-full bg-[#f5f5f7] px-3 py-1.5 text-sm text-[#48484a]">{participant.persons?.full_name ?? participant.ensembles?.name}{participant.role ? ` · ${participant.role}` : ""}</span>)}</div></section>}
        {(works ?? []).length > 0 && <section className="mt-8"><h2 className="text-lg font-semibold text-[#1d1d1f]">Programm</h2><ol className="mt-3 divide-y divide-black/[0.06]">{works!.map((work) => <li key={`${work.position}-${work.works?.title ?? "work"}`} className="py-3"><p className="font-medium text-[#1d1d1f]">{work.works?.title}</p>{work.works?.composer?.full_name && <p className="text-sm text-[#86868b]">{work.works.composer.full_name}</p>}</li>)}</ol></section>}
        {event.ticket_url && <a href={event.ticket_url} target="_blank" rel="noreferrer" className="mt-9 inline-flex rounded-full bg-[#0071e3] px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-[#0077ed]">Tickets kaufen ↗</a>}
      </div>
    </div>
  </div>;
}
