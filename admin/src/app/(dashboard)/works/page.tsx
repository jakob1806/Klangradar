import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { TableSearchFilter } from "@/components/table-search-filter";

type WorkRow = { id: string; title: string; catalog_number: string | null; genre: string | null; composer: { full_name: string } | null; event_works: { count: number }[] };

export default async function WorksPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.from("works").select("id, title, catalog_number, genre, composer:persons(full_name), event_works(count)").order("title").returns<WorkRow[]>();
  return <div className="p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8b2635]">Knowledge Graph</p><h1 className="mt-1 text-2xl font-semibold tracking-[-0.035em]">Werke</h1><p className="mt-1 max-w-xl text-sm text-neutral-500">Repertoire zentral pflegen und Aufführungen über alle Events hinweg verfolgen.</p></div><Link href="/works/new" className="rounded-lg bg-[#8b2635] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#79212e] active:scale-[0.98]">Neues Werk</Link></div>
    {error ? <p className="mt-6 text-sm text-red-700">Werke konnten nicht geladen werden: {error.message}</p> : <div className="mt-7"><TableSearchFilter containerId="works-table" placeholder="Werk oder Komponist:in suchen…" /><div id="works-table" className="mt-3 overflow-hidden rounded-xl border border-black/[0.06] bg-white"><table className="w-full text-sm"><thead className="border-b border-black/[0.06] text-left"><tr><th className="type-label px-4 py-3">Werk</th><th className="type-label px-4 py-3">Komponist:in</th><th className="type-label px-4 py-3">Typ</th><th className="type-label px-4 py-3 text-right">Aufführungen</th></tr></thead><tbody className="divide-y divide-black/[0.06]">{data?.length ? data.map((work) => <tr key={work.id} data-search={`${work.title} ${work.composer?.full_name ?? ""}`.toLowerCase()} className="hover:bg-black/[0.025]"><td className="px-4 py-3"><Link href={`/works/${work.id}`} className="font-medium text-[#1d1d1f] hover:text-[#8b2635]">{work.title}</Link>{work.catalog_number && <span className="ml-2 text-xs text-neutral-400">{work.catalog_number}</span>}</td><td className="px-4 py-3 text-neutral-600">{work.composer?.full_name ?? "—"}</td><td className="px-4 py-3 text-neutral-500">{work.genre ?? "—"}</td><td className="px-4 py-3 text-right font-mono tabular-nums text-neutral-600">{work.event_works?.[0]?.count ?? 0}</td></tr>) : <tr><td colSpan={4} className="px-4 py-12 text-center text-neutral-400">Noch keine Werke angelegt.</td></tr>}</tbody></table></div></div>}
  </div>;
}
