import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card } from "@/components/organizer/ui/card";
import { Input } from "@/components/organizer/ui/input";
import { pageRange, resolveEventImages, type EventImageInput } from "@/lib/library-images";
import { LibraryPagination } from "../pagination";

export const dynamic = "force-dynamic";

type Event = EventImageInput & { title: string; start_datetime: string; venues: { id: string; name: string; photo_url: string | null } | null };

export default async function LibraryEventsPage({ searchParams }: { searchParams: Promise<{ q?: string; page?: string }> }) {
  const { q = "", page: pageParam } = await searchParams;
  const page = Math.max(1, Number.parseInt(pageParam ?? "1", 10) || 1);
  const { from, to } = pageRange(page);
  const supabase = await createClient();
  let request = supabase
    .from("events")
    .select("id,title,start_datetime,image_urls,venues(id,name,photo_url),event_participants(persons(id,photo_url),ensembles(id,photo_url))", { count: "exact" })
    .eq("status", "scheduled")
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true })
    .range(from, to);
  if (q.trim()) request = request.ilike("title", `%${q.trim()}%`);
  const { data, count } = await request.returns<Event[]>();
  const images = await resolveEventImages(supabase, data ?? []);

  return (
    <div>
      <PageHeader eyebrow="Bibliothek" title="Kommende Events" description={`${(count ?? 0).toLocaleString("de-DE")} kommende Veranstaltungen${q.trim() ? " für diese Suche" : ""}.`} />
      <PageBody>
        <div className="mb-6 flex items-center">
          <Link href="/veranstalter/bibliothek" className="text-sm font-medium text-[#2D2A6E] hover:underline">
            ← Bibliothek
          </Link>
        </div>
        <form className="mb-6">
          <Input name="q" defaultValue={q} placeholder="Event suchen …" />
        </form>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {(data ?? []).map((event) => (
            <Link key={event.id} href={`/veranstalter/events/discover/${event.id}`} className="group block">
              <Card className="overflow-hidden transition hover:shadow-md">
                <div className="relative aspect-[16/9] bg-[#111111]/[0.03]">
                  {images.get(event.id) && (
                    <Image src={images.get(event.id)!} alt="" fill className="object-cover" sizes="33vw" unoptimized />
                  )}
                </div>
                <div className="p-4">
                  <h2 className="font-semibold text-[#111111] group-hover:text-[#2D2A6E]">{event.title}</h2>
                  <p className="mt-1 text-sm text-[#6B6B6B]">{event.venues?.name ?? "—"}</p>
                  <p className="mt-1 text-sm text-[#4A4A4A]">{formatMunichDateTime(event.start_datetime)}</p>
                </div>
              </Card>
            </Link>
          ))}
        </div>
        <LibraryPagination basePath="/veranstalter/bibliothek/events" q={q.trim()} page={page} total={count ?? 0} />
        {!(data ?? []).length && <p className="mt-8 text-sm text-[#6B6B6B]">Keine passenden kommenden Events gefunden.</p>}
      </PageBody>
    </div>
  );
}
