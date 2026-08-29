"use client";

import { useActionState, useMemo, useState } from "react";
import { addRosterEntry, type RosterActionState } from "./actions";

type Entry = { id: string; name: string; type: "person" | "ensemble" };
export function RosterForm({ organizers, entries }: { organizers: { id: string; name: string }[]; entries: Entry[] }) {
  const [type, setType] = useState<"person" | "ensemble">("person");
  const [state, action, pending] = useActionState<RosterActionState, FormData>(addRosterEntry, {});
  const options = useMemo(() => entries.filter((entry) => entry.type === type), [entries, type]);
  return <form action={action} className="mt-6 rounded-2xl border border-black/[.06] bg-[#f5f5f7] p-5"><h2 className="font-semibold text-[#1d1d1f]">Profil zum Roster hinzufügen</h2><div className="mt-4 grid gap-3 sm:grid-cols-3"><select required name="organizer_id" className="rounded-xl border border-black/[.12] bg-white px-3 py-2 text-sm"><option value="">Agentur wählen</option>{organizers.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select><select name="entity_type" value={type} onChange={(event) => setType(event.target.value as typeof type)} className="rounded-xl border border-black/[.12] bg-white px-3 py-2 text-sm"><option value="person">Person</option><option value="ensemble">Ensemble</option></select><select required name="entity_id" className="rounded-xl border border-black/[.12] bg-white px-3 py-2 text-sm"><option value="">Profil wählen</option>{options.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></div>{state.error && <p className="mt-3 text-sm text-red-600">{state.error}</p>}{state.success && <p className="mt-3 text-sm text-emerald-700">Zum Roster hinzugefügt.</p>}<button disabled={pending} className="mt-4 rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{pending ? "Speichere…" : "Hinzufügen"}</button></form>;
}
