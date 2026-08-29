import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

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
  const [{ count: events }, { count: persons }, { count: ensembles }, { count: venues }] = await Promise.all([
    supabase.from("events").select("id", { count: "exact", head: true }).eq("status", "scheduled").gte("start_datetime", now),
    supabase.from("persons").select("id", { count: "exact", head: true }),
    supabase.from("ensembles").select("id", { count: "exact", head: true }),
    supabase.from("venues").select("id", { count: "exact", head: true }),
  ]);
  const counts = [events, persons, ensembles, venues];
  return <div className="mx-auto max-w-6xl px-6 py-10"><p className="text-sm font-semibold tracking-wide text-[#0071e3]">KLANGRADAR</p><h1 className="type-heading mt-2 text-3xl text-[#1d1d1f]">Bibliothek</h1><p className="mt-3 max-w-2xl text-[#48484a]">Alles, was Klangradar kennt – zum Entdecken und Nachschlagen. Inhalte in der Bibliothek sind nur lesbar.</p><div className="mt-8 grid gap-4 sm:grid-cols-2">{SECTIONS.map((section, index) => <Link key={section.href} href={section.href} className="group overflow-hidden rounded-2xl border border-black/[0.06] bg-white transition hover:-translate-y-0.5 hover:shadow-lg"><div className="relative h-32 bg-gradient-to-br from-[#e9efff] to-[#f5f5f7]"><span className="absolute bottom-4 left-5 text-3xl font-semibold text-[#1d1d1f]/20">0{index + 1}</span></div><div className="p-5"><div className="flex items-center justify-between"><h2 className="text-xl font-semibold text-[#1d1d1f] group-hover:text-[#0071e3]">{section.title}</h2><span className="text-sm text-[#86868b]">{counts[index] ?? 0}</span></div><p className="mt-2 text-sm leading-6 text-[#48484a]">{section.text}</p><p className="mt-4 text-sm font-medium text-[#0071e3]">Durchsuchen →</p></div></Link>)}</div></div>;
}
