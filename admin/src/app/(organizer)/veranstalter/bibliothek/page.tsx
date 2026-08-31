import Link from "next/link";
import Image from "next/image";
import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card } from "@/components/organizer/ui/card";

export const dynamic = "force-dynamic";

// Gleiche Kachel-Sprache wie "Alles entdecken" oben in der Suche der
// iOS-App (DiscoveryTile in Features/Search/SearchView.swift): Farbverlauf,
// leicht gedrehtes Vorschaubild unten rechts, fetter weißer Titel oben
// links — bewusst dieselben vier Farben in derselben Reihenfolge.
const SECTIONS = [
  { href: "/veranstalter/bibliothek/events", title: "Events", text: "Kommende Konzerte mit Programm, Tickets und Mitwirkenden.", color: "#5856D6" },
  { href: "/veranstalter/bibliothek/personen", title: "Personen", text: "Künstler:innen, Dirigent:innen und Komponist:innen entdecken.", color: "#AF52DE" },
  { href: "/veranstalter/bibliothek/ensembles", title: "Ensembles", text: "Orchester, Chöre und Kammermusikensembles.", color: "#30B0C7" },
  { href: "/veranstalter/bibliothek/venues", title: "Venues", text: "Spielstätten mit Bild, Adresse und Hintergrundinformationen.", color: "#FF9500" },
] as const;

// Dieselbe redaktionelle Kuration wie die "Alles entdecken"-Kacheln in der
// iOS-App (featuredItem(for:) in SearchView.swift): statt eines beliebigen
// Datensatzes ein bewusst gewähltes, wiedererkennbares Motiv pro Kategorie.
// Bach-Fallback ist dasselbe gemeinfreie Wikimedia-Porträt wie in der App,
// falls persons.photo_url für ihn (noch) leer ist.
const BACH_FALLBACK_PHOTO = "https://upload.wikimedia.org/wikipedia/commons/thumb/6/6a/Johann_Sebastian_Bach.jpg/330px-Johann_Sebastian_Bach.jpg";

export default async function LibraryPage() {
  const supabase = await createClient();
  const now = new Date().toISOString();
  const [
    { count: events },
    { count: persons },
    { count: ensembles },
    { count: venues },
    { data: bach },
    { data: brso },
    { data: isarphilharmonie },
    { data: rattle },
  ] = await Promise.all([
    supabase.from("events").select("id", { count: "exact", head: true }).eq("status", "scheduled").gte("start_datetime", now),
    supabase.from("persons").select("id", { count: "exact", head: true }),
    supabase.from("ensembles").select("id", { count: "exact", head: true }),
    supabase.from("venues").select("id", { count: "exact", head: true }),
    supabase.from("persons").select("photo_url").ilike("full_name", "%Johann Sebastian Bach%").limit(1).maybeSingle(),
    supabase.from("ensembles").select("photo_url").ilike("name", "%Bayerischen Rundfunks%").limit(1).maybeSingle(),
    supabase.from("venues").select("photo_url").ilike("name", "%Isarphilharmonie%").limit(1).maybeSingle(),
    supabase.from("persons").select("id").ilike("full_name", "%Rattle%").limit(1).maybeSingle(),
  ]);

  let rattleEventImage: string | null = null;
  if (rattle?.id) {
    const { data: participation } = await supabase
      .from("event_participants")
      .select("events!inner(image_urls, start_datetime, status)")
      .eq("person_id", rattle.id)
      .eq("events.status", "scheduled")
      .gte("events.start_datetime", now)
      .not("events.image_urls", "eq", "{}")
      .order("start_datetime", { referencedTable: "events", ascending: true })
      .limit(1)
      .maybeSingle<{ events: { image_urls: string[] } }>();
    rattleEventImage = participation?.events?.image_urls?.[0] ?? null;
  }
  if (!rattleEventImage) {
    const { data: anyEvent } = await supabase.from("events").select("image_urls").eq("status", "scheduled").gte("start_datetime", now).not("image_urls", "eq", "{}").order("start_datetime", { ascending: true }).limit(1).maybeSingle();
    rattleEventImage = anyEvent?.image_urls?.[0] ?? null;
  }

  const counts = [events, persons, ensembles, venues];
  const covers: (string | null)[] = [
    rattleEventImage,
    bach?.photo_url ?? BACH_FALLBACK_PHOTO,
    brso?.photo_url ?? null,
    isarphilharmonie?.photo_url ?? null,
  ];
  return (
    <div>
      <PageHeader eyebrow="Klangradar" title="Bibliothek" description="Alles, was Klangradar kennt – zum Entdecken und Nachschlagen. Inhalte in der Bibliothek sind nur lesbar." />
      <PageBody>
        <div className="grid gap-4 sm:grid-cols-2">
          {SECTIONS.map((section, index) => (
            <Link key={section.href} href={section.href} className="group block">
              <Card className="overflow-hidden transition hover:-translate-y-0.5 hover:shadow-md">
                <div
                  className="relative h-36 overflow-hidden"
                  style={{ background: `linear-gradient(135deg, ${section.color}, ${section.color}b3)` }}
                >
                  <h2 className="absolute left-4 top-4 text-lg font-bold text-white drop-shadow-sm">{section.title}</h2>
                  <span className="absolute left-4 top-9 text-[13px] font-medium text-white/75">{counts[index] ?? 0} Einträge</span>
                  {covers[index] ? (
                    <div className="absolute -bottom-3 -right-3 size-24 rotate-[9deg] overflow-hidden rounded-xl shadow-lg ring-1 ring-black/10">
                      <Image src={covers[index]!} alt="" fill sizes="96px" className="object-cover" unoptimized />
                    </div>
                  ) : (
                    <div className="absolute -bottom-3 -right-3 flex size-24 rotate-[9deg] items-center justify-center rounded-xl bg-white/15 shadow-lg" />
                  )}
                </div>
                <div className="p-5">
                  <p className="text-sm leading-6 text-[#4a4550]">{section.text}</p>
                  <p className="mt-3 text-sm font-medium text-[#2D2A6E]">Durchsuchen →</p>
                </div>
              </Card>
            </Link>
          ))}
        </div>
      </PageBody>
    </div>
  );
}
