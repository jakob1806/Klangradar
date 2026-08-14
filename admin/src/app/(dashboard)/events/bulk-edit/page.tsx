import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { loadEventFormOptions } from "../form-options";
import { BulkEditForm } from "./bulk-edit-form";
import { BulkEventImageAdd } from "./bulk-event-image-add";
import { formatMunichDateTime } from "@/lib/munich-time";

export const dynamic = "force-dynamic";

export default async function BulkEditEventsPage({
  searchParams,
}: {
  searchParams: Promise<{ ids?: string }>;
}) {
  const { ids } = await searchParams;
  const eventIds = (ids ?? "").split(",").filter(Boolean);

  if (eventIds.length === 0) {
    return (
      <div className="p-8">
        <p className="text-sm text-neutral-500">
          Keine Veranstaltungen ausgewählt. <Link href="/events" className="underline">Zurück zur Liste</Link>.
        </p>
      </div>
    );
  }

  const supabase = await createClient();
  const [{ data: events }, options] = await Promise.all([
    supabase
      .from("events")
      .select("id, title, start_datetime")
      .in("id", eventIds)
      .order("start_datetime", { ascending: true }),
    loadEventFormOptions(),
  ]);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">
          {eventIds.length} Veranstaltungen bearbeiten
        </h1>
        <Link href="/events" className="text-sm font-medium text-neutral-600 hover:text-neutral-900">
          ← Zurück
        </Link>
      </div>
      <p className="mt-1 max-w-xl text-sm text-neutral-500">
        Nur Felder mit angehakter &quot;Übernehmen&quot;-Box werden geändert — alles andere bleibt je Event
        unangetastet.
      </p>

      <div className="mt-4 rounded-lg border border-neutral-200 bg-white p-3">
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-neutral-400">Ausgewählt</p>
        <ul className="flex flex-col gap-1 text-sm text-neutral-700">
          {(events ?? []).map((e) => (
            <li key={e.id}>
              {e.title}
              {e.start_datetime && (
                <span className="text-neutral-400">
                  {" · "}
                  {formatMunichDateTime(e.start_datetime)}
                </span>
              )}
            </li>
          ))}
        </ul>
      </div>

      <div className="mt-6">
        <BulkEventImageAdd eventIds={eventIds} />
      </div>

      <div className="mt-6">
        <BulkEditForm
          eventIds={eventIds}
          venues={options.venues}
          organizers={options.organizers}
          genres={options.genres}
        />
      </div>
    </div>
  );
}
