import Link from "next/link";
import Image from "next/image";
import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card } from "@/components/organizer/ui/card";

export const dynamic = "force-dynamic";

const SECTIONS = [
  { href: "/veranstalter/bibliothek/events", title: "Events", text: "Kommende Konzerte mit Programm, Tickets und Mitwirkenden." },
  { href: "/veranstalter/bibliothek/personen", title: "Personen", text: "Künstler:innen, Dirigent:innen und Komponist:innen entdecken." },
  { href: "/veranstalter/bibliothek/ensembles", title: "Ensembles", text: "Orchester, Chöre und Kammermusikensembles." },
  { href: "/veranstalter/bibliothek/venues", title: "Venues", text: "Spielstätten mit Bild, Adresse und Hintergrundinformationen." },
] as const;

export default async function LibraryPage() {
  const supabase = await createClient();
  const now = new Date().toISOString();
  const [
    { count: events },
    { count: persons },
    { count: ensembles },
    { count: venues },
    { data: eventCover },
    { data: personCover },
    { data: ensembleCover },
    { data: venueCover },
  ] = await Promise.all([
    supabase.from("events").select("id", { count: "exact", head: true }).eq("status", "scheduled").gte("start_datetime", now),
    supabase.from("persons").select("id", { count: "exact", head: true }),
    supabase.from("ensembles").select("id", { count: "exact", head: true }),
    supabase.from("venues").select("id", { count: "exact", head: true }),
    supabase.from("events").select("image_urls").eq("status", "scheduled").gte("start_datetime", now).not("image_urls", "eq", "{}").order("start_datetime", { ascending: true }).limit(1).maybeSingle(),
    supabase.from("persons").select("photo_url").not("photo_url", "is", null).limit(1).maybeSingle(),
    supabase.from("ensembles").select("photo_url").not("photo_url", "is", null).limit(1).maybeSingle(),
    supabase.from("venues").select("photo_url").not("photo_url", "is", null).limit(1).maybeSingle(),
  ]);
  const counts = [events, persons, ensembles, venues];
  const covers: (string | null)[] = [
    eventCover?.image_urls?.[0] ?? null,
    personCover?.photo_url ?? null,
    ensembleCover?.photo_url ?? null,
    venueCover?.photo_url ?? null,
  ];
  return (
    <div>
      <PageHeader eyebrow="Klangradar" title="Bibliothek" description="Alles, was Klangradar kennt – zum Entdecken und Nachschlagen. Inhalte in der Bibliothek sind nur lesbar." />
      <PageBody>
        <div className="grid gap-4 sm:grid-cols-2">
          {SECTIONS.map((section, index) => (
            <Link key={section.href} href={section.href} className="group block">
              <Card className="overflow-hidden transition hover:-translate-y-0.5 hover:shadow-md">
                <div className="relative h-32 bg-gradient-to-br from-[#2D2A6E]/[0.06] to-[#15131a]/[0.03]">
                  {covers[index] ? (
                    <Image src={covers[index]!} alt="" fill sizes="(min-width: 640px) 50vw, 100vw" className="object-cover" unoptimized />
                  ) : (
                    <span className="absolute bottom-4 left-5 text-3xl font-semibold text-[#15131a]/20">0{index + 1}</span>
                  )}
                </div>
                <div className="p-5">
                  <div className="flex items-center justify-between">
                    <h2 className="text-xl font-semibold text-[#15131a] group-hover:text-[#2D2A6E]">{section.title}</h2>
                    <span className="text-sm text-[#726c78]">{counts[index] ?? 0}</span>
                  </div>
                  <p className="mt-2 text-sm leading-6 text-[#4a4550]">{section.text}</p>
                  <p className="mt-4 text-sm font-medium text-[#2D2A6E]">Durchsuchen →</p>
                </div>
              </Card>
            </Link>
          ))}
        </div>
      </PageBody>
    </div>
  );
}
