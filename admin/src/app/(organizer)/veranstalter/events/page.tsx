import Link from "next/link";
import Image from "next/image";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";

export const dynamic = "force-dynamic";

const STATUS_LABEL: Record<string, string> = {
  scheduled: "Geplant",
  sold_out: "Ausverkauft",
  cancelled: "Abgesagt",
  postponed: "Verschoben",
  draft: "Entwurf",
};

interface EventRow {
  id: string;
  title: string;
  start_datetime: string;
  status: string;
  venues: { name: string } | null;
  image_urls: string[] | null;
}

// Lädt eigene Events implizit über RLS ("Veranstalter sieht eigene Events",
// entity_claims-Migration) — kein manueller organizer_id-Filter nötig, ein
// unauthorisierter Nutzer sähe hier ohnehin nur öffentlich sichtbare Zeilen
// (die RLS-Policies werden pro Command-Typ ODER-verknüpft).
export default async function VeranstalterEventsPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const organizers = await getEventOrganizerOptions();
  const organizerIds = organizers.map((organizer) => organizer.id);
  const { data } = organizerIds.length ? await supabase
    .from("events")
    .select("id, title, start_datetime, status, venues(name), image_urls")
    .in("organizer_id", organizerIds)
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true })
    .returns<EventRow[]>() : { data: [] as EventRow[] };

  const events = data ?? [];

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="type-heading text-2xl text-[#1d1d1f]">Meine Events</h1>
        {organizerIds.length > 0 && <Link href="/veranstalter/events/new" className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#0077ed]">Neu anlegen</Link>}
      </div>

      <p className="-mt-3 mb-6 text-sm text-[#86868b]">Nur kommende Events deiner beanspruchten Profile, chronologisch ab heute.</p>
      {events.length === 0 ? (
        organizerIds.length === 0 ? <p className="text-sm text-[#86868b]">Noch keine Events. Beanspruche zuerst ein Profil unter <Link href="/veranstalter/claim" className="font-medium text-[#0071e3] hover:underline">Beanspruchen</Link>.</p>
        : <p className="text-sm text-[#86868b]">Noch keine kommenden Events. Lege dein erstes Event an.</p>
      ) : (
        <div className="overflow-hidden rounded-xl border border-black/[0.06] bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-black/[0.06] text-left">
              <tr>
                <th className="px-4 py-3 text-xs font-semibold text-[#86868b]">Bild</th>
                <th className="px-4 py-3 text-xs font-semibold text-[#86868b]">Titel</th>
                <th className="px-4 py-3 text-xs font-semibold text-[#86868b]">Ort</th>
                <th className="px-4 py-3 text-xs font-semibold text-[#86868b]">Termin</th>
                <th className="px-4 py-3 text-xs font-semibold text-[#86868b]">Status</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-200">
              {events.map((event) => (
                <tr key={event.id}>
                  <td className="px-4 py-3"><div className="relative h-12 w-16 overflow-hidden rounded-md bg-[#f5f5f7]">{event.image_urls?.[0] && <Image src={event.image_urls[0]} alt="" fill className="object-cover" sizes="64px" unoptimized />}</div></td>
                  <td className="px-4 py-3 font-medium text-[#1d1d1f]">{event.title}</td>
                  <td className="px-4 py-3 text-[#48484a]">{event.venues?.name ?? "—"}</td>
                  <td className="px-4 py-3 tabular-nums text-[#48484a]">{formatMunichDateTime(event.start_datetime)}</td>
                  <td className="px-4 py-3">
                    <span className="rounded-full border border-black/10 bg-black/[0.03] px-2.5 py-1 text-xs font-medium text-[#48484a]">
                      {STATUS_LABEL[event.status] ?? event.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <Link href={`/veranstalter/events/${event.id}`} className="font-medium text-[#0071e3] hover:underline">
                      Bearbeiten
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
