import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card } from "@/components/organizer/ui/card";
import { Input } from "@/components/organizer/ui/input";

export const dynamic = "force-dynamic";

type Event = { id: string; title: string; start_datetime: string; image_urls: string[] | null; venues: { name: string } | null };

export default async function LibraryEventsPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q = "" } = await searchParams;
  const supabase = await createClient();
  let request = supabase
    .from("events")
    .select("id,title,start_datetime,image_urls,venues(name)")
    .eq("status", "scheduled")
    .gte("start_datetime", new Date().toISOString())
    .order("start_datetime", { ascending: true })
    .limit(60);
  if (q.trim()) request = request.ilike("title", `%${q.trim()}%`);
  const { data } = await request.returns<Event[]>();

  return (
    <div>
      <PageHeader eyebrow="Bibliothek" title="Kommende Events" />
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
                <div className="relative aspect-[16/9] bg-[#15131a]/[0.03]">
                  {event.image_urls?.[0] && (
                    <Image src={event.image_urls[0]} alt="" fill className="object-cover" sizes="33vw" unoptimized />
                  )}
                </div>
                <div className="p-4">
                  <h2 className="font-semibold text-[#15131a] group-hover:text-[#2D2A6E]">{event.title}</h2>
                  <p className="mt-1 text-sm text-[#726c78]">{event.venues?.name ?? "—"}</p>
                  <p className="mt-1 text-sm text-[#4a4550]">{formatMunichDateTime(event.start_datetime)}</p>
                </div>
              </Card>
            </Link>
          ))}
        </div>
        {!(data ?? []).length && <p className="mt-8 text-sm text-[#726c78]">Keine passenden kommenden Events gefunden.</p>}
      </PageBody>
    </div>
  );
}
