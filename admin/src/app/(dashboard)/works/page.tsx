import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { TableSearchFilter } from "@/components/table-search-filter";

import { researchAllWorks } from "./actions";
import { SubmitButton } from "@/components/submit-button";

type WorkRow = { id: string; title: string; catalog_number: string | null; genre: string | null; introduction_de: string | null; introduction_source: string | null; introduction_checked_at: string | null; movements: string[] | null; composer: { full_name: string } | null; event_works: { count: number }[] };

const SOURCE_SHORT: Record<string, string> = { wikipedia: "Wikipedia", programmheft: "Programmheft", veranstalter: "Veranstalter", redaktion: "Redaktion" };

export default async function WorksPage({ searchParams }: { searchParams: Promise<{ filter?: string }> }) {
  const { filter } = await searchParams;
  const supabase = await createClient();
  let query = supabase.from("works").select("id, title, catalog_number, genre, introduction_de, introduction_source, introduction_checked_at, movements, composer:persons(full_name), event_works(count)").order("title").range(0, 4999);
  if (filter === "ohne") query = query.is("introduction_de", null);
  if (filter === "ohne-saetze") query = query.is("movements", null);
  const { data, error } = await query.returns<WorkRow[]>();
  const [{ count: total }, { count: withIntro }, { count: withMovements }, { count: unchecked }] = await Promise.all([
    supabase.from("works").select("id", { count: "exact", head: true }),
    supabase.from("works").select("id", { count: "exact", head: true }).not("introduction_de", "is", null),
    supabase.from("works").select("id", { count: "exact", head: true }).not("movements", "is", null),
    supabase.from("works").select("id", { count: "exact", head: true }).is("introduction_checked_at", null),
  ]);
  const chip = (value: string | undefined, label: string) => <Link href={value ? `/works?filter=${value}` : "/works"} className={`rounded-full px-3 py-1 text-xs font-semibold ${filter === value ? "bg-[#8b2635] text-white" : "bg-black/[0.05] text-neutral-700 hover:bg-black/[0.08]"}`}>{label}</Link>;
  return <div className="p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8b2635]">Knowledge Graph</p><h1 className="mt-1 text-2xl font-semibold tracking-[-0.035em]">Werke</h1><p className="mt-1 max-w-xl text-sm text-neutral-500">Repertoire zentral pflegen und Aufführungen über alle Events hinweg verfolgen.</p></div><Link href="/works/new" className="rounded-lg bg-[#8b2635] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#79212e] active:scale-[0.98]">Neues Werk</Link></div>
    <div className="mt-6 grid gap-3 sm:grid-cols-4">
      {[["Werke", total], ["mit Einführung", withIntro], ["mit Satzfolge", withMovements], ["noch nicht recherchiert", unchecked]].map(([label, value]) => <div key={label as string} className="rounded-xl border border-black/[0.06] bg-white p-4"><p className="text-xs text-neutral-500">{label}</p><p className="mt-1 font-mono text-xl font-semibold tabular-nums">{value ?? "–"}</p></div>)}
    </div>
    <form action={researchAllWorks} className="mt-3 flex flex-wrap items-center gap-3 rounded-xl border border-black/[0.06] bg-white p-4"><div className="min-w-0 flex-1"><p className="text-sm font-semibold">Recherche für alle Werke</p><p className="text-xs text-neutral-500">Läuft automatisch alle 5 Minuten (40 Werke je Lauf, Werke kommender Konzerte zuerst). Hier sofort einen Lauf anstoßen.</p></div><SubmitButton>Jetzt einen Lauf starten</SubmitButton></form>
    <div className="mt-5 flex flex-wrap gap-2">{chip(undefined, "Alle")}{chip("ohne", "Ohne Einführung")}{chip("ohne-saetze", "Ohne Satzfolge")}</div>
    {error ? <p className="mt-6 text-sm text-red-700">Werke konnten nicht geladen werden: {error.message}</p> : <div className="mt-7"><TableSearchFilter containerId="works-table" placeholder="Werk oder Komponist:in suchen…" /><div id="works-table" className="mt-3 overflow-hidden rounded-xl border border-black/[0.06] bg-white"><table className="w-full text-sm"><thead className="border-b border-black/[0.06] text-left"><tr><th className="type-label px-4 py-3">Werk</th><th className="type-label px-4 py-3">Komponist:in</th><th className="type-label px-4 py-3">Typ</th><th className="type-label px-4 py-3">Einführung</th><th className="type-label px-4 py-3 text-right">Sätze</th><th className="type-label px-4 py-3 text-right">Aufführungen</th></tr></thead><tbody className="divide-y divide-black/[0.06]">{data?.length ? data.map((work) => <tr key={work.id} data-search={`${work.title} ${work.composer?.full_name ?? ""}`.toLowerCase()} className="hover:bg-black/[0.025]"><td className="px-4 py-3"><Link href={`/works/${work.id}`} className="font-medium text-[#18181B] hover:text-[#8b2635]">{work.title}</Link>{work.catalog_number && <span className="ml-2 text-xs text-neutral-400">{work.catalog_number}</span>}</td><td className="px-4 py-3 text-neutral-600">{work.composer?.full_name ?? "—"}</td><td className="px-4 py-3 text-neutral-500">{work.genre ?? "—"}</td><td className="px-4 py-3 text-xs">{work.introduction_de ? <span className="rounded-full bg-emerald-50 px-2 py-0.5 font-semibold text-emerald-700">{SOURCE_SHORT[work.introduction_source ?? ""] ?? "vorhanden"}</span> : <span className="text-neutral-400">{work.introduction_checked_at ? "nichts gefunden" : "offen"}</span>}</td><td className="px-4 py-3 text-right font-mono tabular-nums text-neutral-600">{work.movements?.length ?? "—"}</td><td className="px-4 py-3 text-right font-mono tabular-nums text-neutral-600">{work.event_works?.[0]?.count ?? 0}</td></tr>) : <tr><td colSpan={6} className="px-4 py-12 text-center text-neutral-400">Noch keine Werke angelegt.</td></tr>}</tbody></table></div></div>}
  </div>;
}
