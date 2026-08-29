"use client";

import { useActionState } from "react";
import { createEventSeries } from "./actions";

type EventOption = { id: string; title: string; startLabel: string; organizerId: string };

const initialState: { error?: string; success?: true } = {};

export function SeriesForm({ organizers, events }: { organizers: { id: string; name: string }[]; events: EventOption[] }) {
  const [state, action, pending] = useActionState(createEventSeries, initialState);
  return <form action={action} className="rounded-2xl border border-black/[.06] bg-[#f5f5f7] p-5">
    <h2 className="text-base font-semibold text-[#1d1d1f]">Neue Serie anlegen</h2>
    <p className="mt-1 text-sm leading-6 text-[#48484a]">Fasse wiederkehrende Termine zusammen. Der Name, die Beschreibung und das Bild dienen als gemeinsame Grundlage; einzelne Events können weiterhin ergänzt werden.</p>
    <div className="mt-5 grid gap-4 sm:grid-cols-2">
      <label className="text-sm font-medium text-[#1d1d1f]">Name der Serie<input required name="title" className="mt-1.5 w-full rounded-xl border border-black/[.12] bg-white px-3 py-2 text-sm" placeholder="z. B. Orgelkonzerte 2026/27" /></label>
      <label className="text-sm font-medium text-[#1d1d1f]">Institution<select required name="organizer_id" className="mt-1.5 w-full rounded-xl border border-black/[.12] bg-white px-3 py-2 text-sm"><option value="">Bitte wählen</option>{organizers.map((organizer) => <option key={organizer.id} value={organizer.id}>{organizer.name}</option>)}</select></label>
    </div>
    <label className="mt-4 block text-sm font-medium text-[#1d1d1f]">Gemeinsame Beschreibung<textarea name="description_de" rows={3} className="mt-1.5 w-full rounded-xl border border-black/[.12] bg-white px-3 py-2 text-sm" placeholder="Optional – gilt als Grundlage für alle Termine." /></label>
    <label className="mt-4 block text-sm font-medium text-[#1d1d1f]">Gemeinsames Bild (https-URL)<input name="image_url" type="url" className="mt-1.5 w-full rounded-xl border border-black/[.12] bg-white px-3 py-2 text-sm" placeholder="https://…" /></label>
    <fieldset className="mt-5"><legend className="text-sm font-medium text-[#1d1d1f]">Termine auswählen</legend><div className="mt-2 max-h-60 divide-y divide-black/[.06] overflow-y-auto rounded-xl border border-black/[.08] bg-white">{events.length === 0 ? <p className="px-3 py-4 text-sm text-[#86868b]">Keine kommenden eigenen Termine vorhanden.</p> : events.map((event) => <label key={event.id} className="flex cursor-pointer items-center gap-3 px-3 py-2.5 text-sm hover:bg-black/[.02]"><input name="event_ids" type="checkbox" value={event.id} /><span className="min-w-0 flex-1 truncate text-[#1d1d1f]">{event.title}</span><span className="text-xs text-[#86868b]">{event.startLabel}</span></label>)}</div></fieldset>
    {state.error && <p className="mt-4 text-sm text-red-600">{state.error}</p>}{state.success && <p className="mt-4 text-sm text-emerald-700">Serie angelegt und Termine zugeordnet.</p>}
    <button disabled={pending || events.length === 0} className="mt-5 rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{pending ? "Lege an…" : "Serie anlegen"}</button>
  </form>;
}
