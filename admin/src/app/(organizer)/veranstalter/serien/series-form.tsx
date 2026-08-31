"use client";

import { useActionState } from "react";
import { createEventSeries } from "./actions";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Input, Textarea } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { Button } from "@/components/organizer/ui/button";

type EventOption = { id: string; title: string; startLabel: string; organizerId: string };

const initialState: { error?: string; success?: true } = {};

export function SeriesForm({ organizers, events }: { organizers: { id: string; name: string }[]; events: EventOption[] }) {
  const [state, action, pending] = useActionState(createEventSeries, initialState);
  return (
    <Card>
      <CardContent className="pt-5">
        <form action={action}>
          <h2 className="text-base font-semibold text-[#15131a]">Neue Serie anlegen</h2>
          <p className="mt-1 text-sm leading-6 text-[#4a4550]">
            Fasse wiederkehrende Termine zusammen. Der Name, die Beschreibung und das Bild dienen als gemeinsame Grundlage; einzelne Events
            können weiterhin ergänzt werden.
          </p>
          <div className="mt-5 grid gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="series-title">Name der Serie</Label>
              <Input required id="series-title" name="title" placeholder="z. B. Orgelkonzerte 2026/27" />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="series-organizer">Institution</Label>
              <select
                required
                id="series-organizer"
                name="organizer_id"
                className="flex h-9 w-full rounded-lg border border-black/10 bg-white px-3 text-sm text-[#15131a] transition focus-visible:border-[#2D2A6E] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2D2A6E]/25"
              >
                <option value="">Bitte wählen</option>
                {organizers.map((organizer) => (
                  <option key={organizer.id} value={organizer.id}>
                    {organizer.name}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div className="mt-4 flex flex-col gap-1.5">
            <Label htmlFor="series-description">Gemeinsame Beschreibung</Label>
            <Textarea id="series-description" name="description_de" rows={3} placeholder="Optional – gilt als Grundlage für alle Termine." />
          </div>
          <div className="mt-4 flex flex-col gap-1.5">
            <Label htmlFor="series-image">Gemeinsames Bild (https-URL)</Label>
            <Input id="series-image" name="image_url" type="url" placeholder="https://…" />
          </div>
          <fieldset className="mt-5">
            <legend className="text-[13px] font-medium text-[#4a4550]">Termine auswählen</legend>
            <div className="mt-2 max-h-60 divide-y divide-[#15131a]/[0.06] overflow-y-auto rounded-lg border border-[#15131a]/[0.08] bg-white">
              {events.length === 0 ? (
                <p className="px-3 py-4 text-sm text-[#726c78]">Keine kommenden eigenen Termine vorhanden.</p>
              ) : (
                events.map((event) => (
                  <label key={event.id} className="flex cursor-pointer items-center gap-3 px-3 py-2.5 text-sm hover:bg-[#15131a]/[0.02]">
                    <input name="event_ids" type="checkbox" value={event.id} />
                    <span className="min-w-0 flex-1 truncate text-[#15131a]">{event.title}</span>
                    <span className="text-xs text-[#726c78]">{event.startLabel}</span>
                  </label>
                ))
              )}
            </div>
          </fieldset>
          {state.error && <p className="mt-4 text-sm text-[#a91551]">{state.error}</p>}
          {state.success && <p className="mt-4 text-sm text-[#175f3c]">Serie angelegt und Termine zugeordnet.</p>}
          <Button type="submit" disabled={pending || events.length === 0} className="mt-5">
            {pending ? "Lege an…" : "Serie anlegen"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
