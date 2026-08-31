import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Card } from "@/components/organizer/ui/card";

export const dynamic = "force-dynamic";

const CONFIG = {
  personen: { table: "persons", label: "Person", name: "full_name", image: "photo_url", bio: "biography_de", extra: ["instrument", "nationality"] },
  ensembles: { table: "ensembles", label: "Ensemble", name: "name", image: "photo_url", bio: "description_de", extra: ["type", "founded_year"] },
  venues: { table: "venues", label: "Venue", name: "name", image: "photo_url", bio: "description_de", extra: ["address_street", "address_zip", "address_city", "website_url", "capacity"] },
} as const;
type Kind = keyof typeof CONFIG;

export default async function LibraryEntityDetailPage({ params }: { params: Promise<{ kind: string; id: string }> }) {
  const { kind, id } = await params;
  if (!(kind in CONFIG)) notFound();
  const config = CONFIG[kind as Kind];
  const supabase = await createClient();
  const fields = ["id", config.name, config.image, config.bio, "gallery_urls", ...config.extra].join(", ");
  const { data } = await supabase.from(config.table).select(fields).eq("id", id).maybeSingle();
  if (!data) notFound();
  const row = data as unknown as Record<string, unknown>;
  const gallery = [row[config.image], ...(((row.gallery_urls as string[] | null) ?? []))].filter(
    (value): value is string => typeof value === "string"
  );

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <Link href={`/veranstalter/bibliothek/${kind}`} className="text-sm font-medium text-[#2D2A6E] hover:underline">
        ← {kind}
      </Link>
      <Card className="mt-5 overflow-hidden">
        <div className="relative aspect-[16/8] bg-[#15131a]/[0.03]">
          {gallery[0] ? (
            <Image src={gallery[0]} alt="" fill priority className="object-cover" sizes="896px" unoptimized />
          ) : (
            <span className="absolute inset-0 flex items-center justify-center text-6xl font-semibold text-[#726c78]">
              {String(row[config.name]).slice(0, 1)}
            </span>
          )}
        </div>
        <div className="p-6 sm:p-9">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#2D2A6E]">{config.label}</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-[#15131a]">{String(row[config.name])}</h1>
          <div className="mt-6 grid gap-4 border-y border-[#15131a]/[0.08] py-5 sm:grid-cols-2">
            {config.extra.map(
              (field) =>
                row[field] !== null &&
                row[field] !== undefined && (
                  <div key={field}>
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-[#726c78]">{field.replaceAll("_", " ")}</p>
                    <p className="mt-1 text-[#15131a]">{String(row[field])}</p>
                  </div>
                )
            )}
          </div>
          {row[config.bio] ? (
            <section className="mt-8">
              <h2 className="text-lg font-semibold text-[#15131a]">Biographie & Informationen</h2>
              <p className="mt-3 whitespace-pre-wrap leading-7 text-[#4a4550]">{String(row[config.bio])}</p>
            </section>
          ) : (
            <p className="mt-8 text-sm text-[#726c78]">Zu diesem Eintrag liegt noch keine ausführliche Beschreibung vor.</p>
          )}
          {gallery.length > 1 && (
            <section className="mt-8">
              <h2 className="text-lg font-semibold text-[#15131a]">Bilder</h2>
              <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
                {gallery.slice(1).map((src, index) => (
                  <div key={`${src}-${index}`} className="relative aspect-square overflow-hidden rounded-lg">
                    <Image src={src} alt="" fill className="object-cover" sizes="200px" unoptimized />
                  </div>
                ))}
              </div>
            </section>
          )}
        </div>
      </Card>
    </div>
  );
}
