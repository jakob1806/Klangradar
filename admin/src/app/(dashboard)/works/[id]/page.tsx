import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { EntityConnections } from "@/components/entity-connections";
import { researchWork, updateWork } from "../actions";
import { SubmitButton } from "@/components/submit-button";
import { WorkForm, type WorkFormValues } from "../work-form";

export default async function EditWorkPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params; const supabase = await createClient();
  const [{ data: work }, { data: persons }] = await Promise.all([
    supabase.from("works").select("title, composer_id, catalog_number, key_signature, composition_year, duration_minutes, genre, instrumentation, description_de, introduction_de, introduction_source, introduction_source_url, movements, movements_source").eq("id", id).maybeSingle<WorkFormValues>(),
    supabase.from("persons").select("id, full_name").order("full_name").returns<{ id: string; full_name: string }[]>(),
  ]);
  if (!work) notFound();
  return <div className="p-8"><Link href="/works" className="text-sm text-neutral-500 hover:text-neutral-800">← Zurück zu Werke</Link><div className="mt-3"><p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8b2635]">Werkprofil</p><h1 className="mt-1 text-2xl font-semibold tracking-[-0.035em]">{work.title}</h1></div><form action={researchWork.bind(null, id)} className="mt-5 flex flex-wrap items-center gap-3 rounded-xl border border-black/[0.06] bg-white p-4"><div className="min-w-0 flex-1"><p className="text-sm font-semibold">Automatisch recherchieren</p><p className="text-xs text-neutral-500">Sucht Werkeinführung und Satzfolge in Wikipedia (de/en). Redaktionstexte bleiben unangetastet.</p></div><SubmitButton>Recherche starten</SubmitButton></form><div className="mt-7"><WorkForm action={updateWork.bind(null, id)} initial={work} persons={persons ?? []} /></div><EntityConnections kind="work" id={id} /></div>;
}
