import { createClient } from "@/lib/supabase/server";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { RosterForm } from "./roster-form";
import { ConfirmButton } from "@/components/confirm-button";
import { removeRosterEntry } from "./actions";

export const dynamic = "force-dynamic";
type Roster = { id: string; organizer_id: string; entity_type: "person" | "ensemble"; entity_id: string };

export default async function AgencyPage() {
  const supabase = await createClient();
  const [organizers, { data: rosterData }, { data: persons }, { data: ensembles }] = await Promise.all([
    getEventOrganizerOptions(),
    supabase.from("organizer_agency_roster").select("id, organizer_id, entity_type, entity_id").returns<Roster[]>(),
    supabase.from("persons").select("id, full_name").order("full_name").limit(500),
    supabase.from("ensembles").select("id, name").order("name").limit(500),
  ]);
  const roster = rosterData ?? [];
  const entries = [...(persons ?? []).map((item) => ({ id: item.id as string, name: item.full_name as string, type: "person" as const })), ...(ensembles ?? []).map((item) => ({ id: item.id as string, name: item.name as string, type: "ensemble" as const }))];
  const nameById = new Map(entries.map((item) => [`${item.type}:${item.id}`, item.name]));
  const organizerById = new Map(organizers.map((item) => [item.id, item.name]));
  return <div className="mx-auto max-w-5xl px-6 py-10"><h1 className="type-heading text-2xl text-[#1d1d1f]">Agentur & Artist Roster</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-[#48484a]">Verwalte Personen und Ensembles, die deine Agentur repräsentiert. Die Einträge bleiben zunächst rein redaktionell.</p><RosterForm organizers={organizers} entries={entries} /><section className="mt-10"><h2 className="text-lg font-semibold text-[#1d1d1f]">Mein Roster</h2>{roster.length === 0 ? <p className="mt-3 text-sm text-[#86868b]">Noch keine Künstler oder Ensembles hinzugefügt.</p> : <div className="mt-3 overflow-hidden rounded-2xl border border-black/[.06] bg-white"><table className="w-full text-sm"><tbody className="divide-y divide-black/[.06]">{roster.map((item) => <tr key={item.id}><td className="px-4 py-3 font-medium text-[#1d1d1f]">{nameById.get(`${item.entity_type}:${item.entity_id}`) ?? "Unbekanntes Profil"}</td><td className="px-4 py-3 text-[#86868b]">{item.entity_type === "person" ? "Person" : "Ensemble"}</td><td className="px-4 py-3 text-[#86868b]">{organizerById.get(item.organizer_id)}</td><td className="px-4 py-3 text-right"><ConfirmButton action={removeRosterEntry.bind(null, item.id)} confirmMessage="Aus dem Roster entfernen?" label="Entfernen" pendingLabel="Entferne…" className="text-sm text-red-700" /></td></tr>)}</tbody></table></div>}</section></div>;
}
