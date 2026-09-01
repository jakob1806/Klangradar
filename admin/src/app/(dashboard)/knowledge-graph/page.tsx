import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

const entities = [
  { label: "Personen", table: "persons", href: "/persons", description: "Künstler:innen, Dirigent:innen und Komponist:innen" },
  { label: "Ensembles", table: "ensembles", href: "/ensembles", description: "Orchester, Chöre und Kammermusikformationen" },
  { label: "Werke", table: "works", href: "/works", description: "Repertoire, Urheberschaft und Aufführungshistorie" },
  { label: "Events", table: "events", href: "/events", description: "Programme verbinden alle Entitäten miteinander" },
  { label: "Venues", table: "venues", href: "/venues", description: "Spielstätten und ihre lokale Aufführungsgeschichte" },
  { label: "Veranstalter", table: "organizers", href: "/organizers", description: "Institutionen hinter Programmen und Reihen" },
  { label: "Festivals", table: "festivals", href: "/festivals", description: "Zeitlich und kuratorisch gebündelte Programme" },
] as const;

export default async function KnowledgeGraphPage() {
  const supabase = await createClient();
  const counts = await Promise.all(entities.map(async (entity) => {
    const { count } = await supabase.from(entity.table).select("id", { count: "exact", head: true });
    return count ?? 0;
  }));
  const [{ count: participantLinks }, { count: workLinks }] = await Promise.all([
    supabase.from("event_participants").select("id", { count: "exact", head: true }),
    supabase.from("event_works").select("event_id", { count: "exact", head: true }),
  ]);

  return <div className="p-8 xl:p-10">
    <section className="grid gap-10 border-b border-black/[0.08] pb-10 xl:grid-cols-[1.2fr_.8fr] xl:items-end">
      <div><p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#8b2635]">Klangradar Datenbank</p><h1 className="mt-3 max-w-4xl text-balance text-[clamp(2.5rem,5vw,4.8rem)] font-semibold leading-[0.94] tracking-[-0.06em] text-[#171714]">Klassische Musik als lebendiges Netzwerk.</h1></div>
      <div><p className="max-w-lg text-pretty text-sm leading-6 text-[#5f5b56]">Nicht nur einzelne Datensätze: Personen, Ensembles, Werke, Orte und Veranstalter werden über reale Aufführungen miteinander verbunden.</p><div className="mt-5 flex gap-8"><GraphMetric value={participantLinks ?? 0} label="Besetzungen" /><GraphMetric value={workLinks ?? 0} label="Programmverknüpfungen" /></div></div>
    </section>

    <section className="mt-10 grid gap-px overflow-hidden rounded-2xl bg-black/[0.08] sm:grid-cols-2 xl:grid-cols-3">
      {entities.map((entity, index) => <Link key={entity.table} href={entity.href} className={`group min-h-48 bg-[#faf9f6] p-6 transition hover:bg-white ${index === 2 ? "xl:row-span-2 xl:min-h-96" : ""}`}><div className="flex items-start justify-between gap-4"><span className="font-mono text-xs text-[#99948c]">0{index + 1}</span><span className="font-mono text-lg tabular-nums text-[#1d1d1f]">{counts[index].toLocaleString("de-DE")}</span></div><h2 className={`${index === 2 ? "mt-20 text-3xl" : "mt-10 text-xl"} font-semibold tracking-[-0.04em] text-[#1d1d1f]`}>{entity.label}</h2><p className="mt-2 max-w-xs text-sm leading-5 text-[#77736d]">{entity.description}</p><span className="mt-5 inline-block text-sm font-semibold text-[#8b2635] transition-transform group-hover:translate-x-1">Öffnen →</span></Link>)}
    </section>

    <section className="mt-12 grid gap-8 border-y border-black/[0.08] py-9 lg:grid-cols-[.7fr_1.3fr]"><div><p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8b2635]">Redaktionelle Fragen</p><h2 className="mt-2 text-2xl font-semibold tracking-[-0.04em]">Der Graph wird mit jedem gepflegten Programm wertvoller.</h2></div><div className="grid gap-x-8 sm:grid-cols-2">{["Wann wurde dieses Werk zuletzt in München gespielt?", "Welche Dirigent:innen interpretieren häufig Mahler?", "Welche Orchester spielen dieses Jahr Rachmaninow?", "Wo tritt diese Sängerin demnächst auf?"].map((question) => <div key={question} className="border-b border-black/[0.08] py-4 text-sm font-medium leading-6 text-[#373531]">„{question}“</div>)}</div></section>
  </div>;
}

function GraphMetric({ value, label }: { value: number; label: string }) { return <div><p className="font-mono text-2xl tabular-nums tracking-[-0.05em] text-[#1d1d1f]">{value.toLocaleString("de-DE")}</p><p className="mt-1 text-xs text-[#77736d]">{label}</p></div>; }
