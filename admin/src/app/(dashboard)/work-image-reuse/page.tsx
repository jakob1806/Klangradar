import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import { RunWorkImageReuseButton } from "@/components/run-work-image-reuse-button";
import { WorkImageManualLink } from "@/components/work-image-manual-link";
import { createClient } from "@/lib/supabase/server";
import { rejectWorkImageReuse } from "@/lib/work-image-reuse-actions";

export const dynamic = "force-dynamic";

interface FlagRow {
  id: string;
  matched_entity_type: "person" | "ensemble";
  matched_entity_id: string;
  matched_venue: boolean;
  created_at: string;
  event: { id: string; title: string; start_datetime: string } | null;
  donor: { id: string; title: string; start_datetime: string } | null;
  work: { id: string; title: string } | null;
  image: { id: string; storage_path: string | null; thumbnail_path: string | null; source_url: string } | null;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

function thumbnailSrc(
  supabase: Awaited<ReturnType<typeof createClient>>,
  image: FlagRow["image"],
): string | null {
  if (!image) return null;
  const path = image.thumbnail_path ?? image.storage_path;
  if (!path) return image.source_url;
  return supabase.storage.from("ingested-images").getPublicUrl(path).data.publicUrl;
}

export default async function WorkImageReusePage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("event_image_reuse")
    .select(
      `id, matched_entity_type, matched_entity_id, matched_venue, created_at,
       event:events!event_image_reuse_event_id_fkey(id, title, start_datetime),
       donor:events!event_image_reuse_donor_event_id_fkey(id, title, start_datetime),
       work:works(id, title),
       image:images(id, storage_path, thumbnail_path, source_url)`,
    )
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .returns<FlagRow[]>();

  const personIds = (data ?? []).filter((f) => f.matched_entity_type === "person").map((f) => f.matched_entity_id);
  const ensembleIds = (data ?? []).filter((f) => f.matched_entity_type === "ensemble").map((f) => f.matched_entity_id);

  const [{ data: persons }, { data: ensembles }] = await Promise.all([
    personIds.length
      ? supabase.from("persons").select("id, full_name").in("id", personIds)
      : Promise.resolve({ data: [] as { id: string; full_name: string }[] }),
    ensembleIds.length
      ? supabase.from("ensembles").select("id, name").in("id", ensembleIds)
      : Promise.resolve({ data: [] as { id: string; name: string }[] }),
  ]);
  const entityNameById = new Map<string, string>([
    ...(persons ?? []).map((p): [string, string] => [p.id, p.full_name]),
    ...(ensembles ?? []).map((e): [string, string] => [e.id, e.name]),
  ]);

  return (
    <div className="p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Werk-Bild-Verknüpfungen</h1>
          <p className="mt-1 max-w-xl text-sm text-neutral-500">
            Veranstaltungen ohne eigenes Bild, denen automatisch das Bild einer anderen Veranstaltung mit demselben
            Werk zugeordnet wurde — entweder dasselbe Ensemble (unabhängig von der Venue) oder dieselbe Person an
            derselben Venue. Bei einer falschen Zuordnung hier ablehnen; die Veranstaltung verliert dann das Bild
            wieder und die Kombination wird nicht erneut automatisch vorgeschlagen.
          </p>
        </div>
        <RunWorkImageReuseButton />
      </div>

      <div className="mt-6">
        <WorkImageManualLink />
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Verknüpfungen nicht laden: {error.message}</p>}

      {!error && (
        <div className="mt-6 flex flex-col gap-3">
          {data && data.length > 0 ? (
            data.map((flag) => {
              const thumb = thumbnailSrc(supabase, flag.image);
              return (
                <div key={flag.id} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div className="flex min-w-0 flex-1 gap-3">
                      {thumb && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={thumb} alt="" className="h-16 w-16 shrink-0 rounded-md object-cover" />
                      )}
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          {flag.event ? (
                            <Link
                              href={`/events/${flag.event.id}`}
                              className="text-sm font-semibold text-neutral-900 hover:text-[#0071e3]"
                            >
                              {flag.event.title}
                            </Link>
                          ) : (
                            <span className="text-sm text-neutral-400">(Veranstaltung gelöscht)</span>
                          )}
                          <span className="text-xs text-neutral-400">{formatDate(flag.created_at)}</span>
                        </div>
                        <p className="mt-1 text-xs text-neutral-600">
                          Werk „{flag.work?.title ?? "—"}“ · {flag.matched_entity_type === "ensemble" ? "Ensemble" : "Person"}{" "}
                          {entityNameById.get(flag.matched_entity_id) ?? flag.matched_entity_id}
                          {flag.matched_venue ? " · gleiche Venue" : " · andere Venue"}
                        </p>
                        {flag.donor && (
                          <Link
                            href={`/events/${flag.donor.id}`}
                            className="mt-1 inline-block text-xs text-blue-700 hover:underline"
                          >
                            Bild übernommen von „{flag.donor.title}“ ({formatDate(flag.donor.start_datetime)}) →
                          </Link>
                        )}
                      </div>
                    </div>
                    <div className="flex shrink-0 flex-col items-end gap-2">
                      {flag.event && (
                        <Link
                          href={`/events/${flag.event.id}`}
                          className="text-xs font-medium text-neutral-700 hover:text-[#0071e3]"
                        >
                          Bearbeiten →
                        </Link>
                      )}
                      <ConfirmButton
                        action={rejectWorkImageReuse.bind(null, flag.id)}
                        confirmMessage="Verknüpfung ablehnen und Bild entfernen?"
                        label="Ablehnen"
                        pendingLabel="…"
                        className="border-2 border-red-700 bg-white px-2.5 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 disabled:opacity-50"
                      />
                    </div>
                  </div>
                </div>
              );
            })
          ) : (
            <p className="text-sm text-neutral-500">
              Keine aktiven Werk-Bild-Verknüpfungen. Auf &quot;Werk-Bilder verknüpfen&quot; klicken, um bildlose
              Veranstaltungen zu prüfen.
            </p>
          )}
        </div>
      )}
    </div>
  );
}
