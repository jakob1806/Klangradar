import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card } from "@/components/organizer/ui/card";
import { Input } from "@/components/organizer/ui/input";

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
  searchParams: Promise<{ q?: string }>;
}) {
  const { kind } = await params;
  const { q = "" } = await searchParams;
  if (!(kind in CONFIG)) notFound();
  const config = CONFIG[kind as Kind];
  const supabase = await createClient();
  let request = supabase
    .from(config.table)
    .select(`id, ${config.name}, ${config.image}, ${config.text}`)
    .order(config.name)
    .limit(60);
  if (q.trim()) request = request.ilike(config.name, `%${q.trim()}%`);
  const { data } = await request;
  const rows = (data ?? []) as Array<Record<string, string | null>>;

  return (
    <div>
      <PageHeader eyebrow="Bibliothek" title={config.title} />
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
                <div className="relative aspect-[4/3] bg-[#15131a]/[0.03]">
                  {row[config.image] ? (
                    <Image src={row[config.image]!} alt="" fill className="object-cover" sizes="33vw" unoptimized />
                  ) : (
                    <span className="absolute inset-0 flex items-center justify-center text-3xl font-semibold text-[#726c78]">
                      {row[config.name]?.slice(0, 1)}
                    </span>
                  )}
                </div>
                <div className="p-4">
                  <h2 className="font-semibold text-[#15131a] group-hover:text-[#2D2A6E]">{row[config.name]}</h2>
                  {row[config.text] && <p className="mt-2 line-clamp-2 text-sm leading-5 text-[#726c78]">{row[config.text]}</p>}
                </div>
              </Card>
            </Link>
          ))}
        </div>
        {!rows.length && <p className="mt-8 text-sm text-[#726c78]">Keine passenden Einträge gefunden.</p>}
      </PageBody>
    </div>
  );
}
