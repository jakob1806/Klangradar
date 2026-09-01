import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";

type EntityKind = "person" | "ensemble" | "venue" | "work";
type EventRow = { id: string; title: string; start_datetime: string; venues: { name: string } | null };
type WorkRow = { id: string; title: string; catalog_number: string | null; composer: { full_name: string } | null };

export async function EntityConnections({ kind, id }: { kind: EntityKind; id: string }) {
  const supabase = await createClient();
  const now = new Date().toISOString();
  let eventIds: string[] | null = null;

  if (kind === "person" || kind === "ensemble") {
    const column = kind === "person" ? "person_id" : "ensemble_id";
    const { data } = await supabase.from("event_participants").select("event_id").eq(column, id).returns<{ event_id: string }[]>();
    eventIds = Array.from(new Set((data ?? []).map((row) => row.event_id)));
  } else if (kind === "work") {
    const { data } = await supabase.from("event_works").select("event_id").eq("work_id", id).returns<{ event_id: string }[]>();
    eventIds = Array.from(new Set((data ?? []).map((row) => row.event_id)));
  }

  let eventQuery = supabase
    .from("events")
    .select("id, title, start_datetime, venues(name)")
    .gte("start_datetime", now)
    .order("start_datetime", { ascending: true })
    .limit(8);
  if (kind === "venue") eventQuery = eventQuery.eq("venue_id", id);
  else if (eventIds?.length) eventQuery = eventQuery.in("id", eventIds);

  const { data: events } = eventIds && eventIds.length === 0
    ? { data: [] as EventRow[] }
    : await eventQuery.returns<EventRow[]>();

  const upcoming = events ?? [];
  const upcomingIds = upcoming.map((event) => event.id);
  const eventWorkLinks = upcomingIds.length
    ? await supabase.from("event_works").select("work_id").in("event_id", upcomingIds).returns<{ work_id: string }[]>()
    : { data: [] as { work_id: string }[] };
  const linkedWorkIds = Array.from(new Set((eventWorkLinks.data ?? []).map((row) => row.work_id)));

  let works: WorkRow[] = [];
  if (kind === "work") {
    const { data } = await supabase.from("works").select("id, title, catalog_number, composer:persons(full_name)").eq("id", id).returns<WorkRow[]>();
    works = data ?? [];
  } else {
    const ids = new Set(linkedWorkIds);
    if (kind === "person") {
      const { data: composed } = await supabase.from("works").select("id").eq("composer_id", id).returns<{ id: string }[]>();
      for (const work of composed ?? []) ids.add(work.id);
    }
    if (ids.size) {
      const { data } = await supabase.from("works").select("id, title, catalog_number, composer:persons(full_name)").in("id", [...ids]).order("title").limit(12).returns<WorkRow[]>();
      works = data ?? [];
    }
  }

  return (
    <section className="mt-10 border-t border-black/[0.08] pt-8" aria-labelledby="connections-heading">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8b2635]">Knowledge Graph</p>
          <h2 id="connections-heading" className="mt-1 text-lg font-semibold tracking-[-0.025em] text-[#1d1d1f]">Verbindungen & nächste Termine</h2>
        </div>
        <Link href="/knowledge-graph" className="text-xs font-semibold text-[#8b2635] hover:underline">Im Graph erkunden →</Link>
      </div>

      <div className="mt-5 grid gap-8 xl:grid-cols-[1.15fr_.85fr]">
        <div>
          <div className="flex items-center justify-between border-b border-black/[0.08] pb-2">
            <h3 className="text-sm font-semibold text-[#292825]">Kommende Veranstaltungen</h3>
            <span className="font-mono text-xs tabular-nums text-[#86827b]">{upcoming.length}</span>
          </div>
          {upcoming.length ? (
            <ol className="divide-y divide-black/[0.07]">
              {upcoming.map((event) => (
                <li key={event.id} className="grid gap-1 py-3 sm:grid-cols-[8.5rem_minmax(0,1fr)] sm:gap-4">
                  <time className="font-mono text-[11px] tabular-nums text-[#77736d]">{formatMunichDateTime(event.start_datetime)}</time>
                  <div className="min-w-0"><Link href={`/events/${event.id}`} className="block truncate text-sm font-medium text-[#1d1d1f] hover:text-[#8b2635]">{event.title}</Link><p className="mt-0.5 truncate text-xs text-[#86827b]">{event.venues?.name ?? "Venue noch offen"}</p></div>
                </li>
              ))}
            </ol>
          ) : <p className="py-6 text-sm text-[#86827b]">Keine kommenden Veranstaltungen verknüpft.</p>}
        </div>

        <div>
          <div className="flex items-center justify-between border-b border-black/[0.08] pb-2">
            <h3 className="text-sm font-semibold text-[#292825]">Assoziierte Werke</h3>
            <span className="font-mono text-xs tabular-nums text-[#86827b]">{works.length}</span>
          </div>
          {works.length ? (
            <ul className="divide-y divide-black/[0.07]">
              {works.map((work) => <li key={work.id} className="py-3"><Link href={`/works/${work.id}`} className="text-sm font-medium text-[#1d1d1f] hover:text-[#8b2635]">{work.title}</Link><p className="mt-0.5 text-xs text-[#86827b]">{[work.composer?.full_name, work.catalog_number].filter(Boolean).join(" · ") || "Urheberschaft noch offen"}</p></li>)}
            </ul>
          ) : <p className="py-6 text-sm text-[#86827b]">Noch keine Werke über Programme verbunden.</p>}
        </div>
      </div>
    </section>
  );
}
