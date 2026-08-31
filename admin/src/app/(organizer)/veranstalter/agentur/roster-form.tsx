"use client";

import { useActionState, useMemo, useState } from "react";
import { addRosterEntry, type RosterActionState } from "./actions";
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "@/components/organizer/ui/card";
import { Button } from "@/components/organizer/ui/button";

type Entry = { id: string; name: string; type: "person" | "ensemble" };

const selectClassName =
  "flex h-9 w-full rounded-lg border border-black/10 bg-white px-3 text-sm text-[#15131a] transition focus-visible:border-[#2D2A6E] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2D2A6E]/25 disabled:cursor-not-allowed disabled:opacity-50";

export function RosterForm({ organizers, entries }: { organizers: { id: string; name: string }[]; entries: Entry[] }) {
  const [type, setType] = useState<"person" | "ensemble">("person");
  const [state, action, pending] = useActionState<RosterActionState, FormData>(addRosterEntry, {});
  const options = useMemo(() => entries.filter((entry) => entry.type === type), [entries, type]);
  return (
    <Card>
      <form action={action}>
        <CardHeader>
          <CardTitle>Profil zum Roster hinzufügen</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-3 sm:grid-cols-3">
            <select required name="organizer_id" className={selectClassName}>
              <option value="">Agentur wählen</option>
              {organizers.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
            <select
              name="entity_type"
              value={type}
              onChange={(event) => setType(event.target.value as typeof type)}
              className={selectClassName}
            >
              <option value="person">Person</option>
              <option value="ensemble">Ensemble</option>
            </select>
            <select required name="entity_id" className={selectClassName}>
              <option value="">Profil wählen</option>
              {options.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
          </div>
          {state.error && <p className="mt-3 text-sm text-[#a91551]">{state.error}</p>}
          {state.success && <p className="mt-3 text-sm text-[#175f3c]">Zum Roster hinzugefügt.</p>}
        </CardContent>
        <CardFooter>
          <Button type="submit" disabled={pending}>
            {pending ? "Speichere…" : "Hinzufügen"}
          </Button>
        </CardFooter>
      </form>
    </Card>
  );
}
