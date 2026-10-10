import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card } from "@/components/organizer/ui/card";
import { Input } from "@/components/organizer/ui/input";
import { loadGalleryImages, pageRange } from "@/lib/library-images";
import { LibraryPagination } from "../pagination";

export const dynamic = "force-dynamic";

const CONFIG = {
  personen: { table: "persons", title: "Personen", name: "full_name", image: "photo_url", text: "biography_de" },
  ensembles: { table: "ensembles", title: "Ensembles", name: "name", image: "photo_url", text: "description_de" },
  venues: { table: "venues", title: "Venues", name: "name", image: "photo_url", text: "description_de" },
} as const;
type Kind = keyof typeof CONFIG;

export default async function LibraryEntitiesPage({
  params,
  searchParams,
}: {
  params: Promise<{ kind: string }>;
  searchParams: Promise<{ q?: string; page?: string }>;
}) {
  const { kind } = await params;
  const { q = "", page: pageParam } = await searchParams;
  const page = Math.max(1, Number.parseInt(pageParam ?? "1", 10) || 1);
  const { from, to } = pageRange(page);
  if (!(kind in CONFIG)) notFound();
  const config = CONFIG[kind as Kind];
  const supabase = await createClient();
  let request = supabase
    .from(config.table)
    .select(`id, ${config.name}, ${config.image}, ${config.text}`, { count: "exact" })
    .order(config.name)
    .range(from, to);
  if (q.trim()) request = request.ilike(config.name, `%${q.trim()}%`);
  const { data, count } = await request;
  const rows = (data ?? []) as unknown as Array<Record<string, string | null>>;
  const gallery = await loadGalleryImages(supabase, rows.map((row) => row.id as string));
  const imageFor = (row: Record<string, string | null>) => gallery.get(row.id as string) ?? row[config.image];

  return (
    <div>
      <PageHeader eyebrow="Bibliothek" title={config.title} description={`${(count ?? 0).toLocaleString("de-DE")} Einträge${q.trim() ? " für diese Suche" : ""}.`} />
      <PageBody>
        <div className="mb-6 flex items-center">
          <Link href="/veranstalter/bibliothek" className="text-sm font-medium text-[#2D2A6E] hover:underline">
            ← Bibliothek
          </Link>
        </div>
        <form className="mb-6">
          <Input name="q" defaultValue={q} placeholder={`${config.title.slice(0, -1)} suchen …`} />
        </form>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {rows.map((row) => (
            <Link key={row.id} href={`/veranstalter/bibliothek/${kind}/${row.id}`} className="group block">
              <Card className="overflow-hidden transition hover:shadow-md">
                <div className="relative aspect-[4/3] bg-[#111111]/[0.03]">
                  {imageFor(row) ? (
                    <Image src={imageFor(row)!} alt="" fill className="object-cover" sizes="33vw" unoptimized />
                  ) : (
                    <span className="absolute inset-0 flex items-center justify-center text-3xl font-semibold text-[#6B6B6B]">
                      {row[config.name]?.slice(0, 1)}
                    </span>
                  )}
                </div>
                <div className="p-4">
                  <h2 className="font-semibold text-[#111111] group-hover:text-[#2D2A6E]">{row[config.name]}</h2>
                  {row[config.text] && <p className="mt-2 line-clamp-2 text-sm leading-5 text-[#6B6B6B]">{row[config.text]}</p>}
                </div>
              </Card>
            </Link>
          ))}
        </div>
        <LibraryPagination basePath={`/veranstalter/bibliothek/${kind}`} q={q.trim()} page={page} total={count ?? 0} />
        {!rows.length && <p className="mt-8 text-sm text-[#6B6B6B]">Keine passenden Einträge gefunden.</p>}
      </PageBody>
    </div>
  );
}
