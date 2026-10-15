"use client";

import { useActionState, useState } from "react";
import { checkOrSubmitFeed, type FeedFormState } from "./actions";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Input } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { Button } from "@/components/organizer/ui/button";

const initialState: FeedFormState = {};
const TYPE_LABEL = { ical: "iCal-Kalender", rss: "RSS-Feed", schema_org: "Webseite mit Event-Daten" } as const;

export function FeedForm({ organizers }: { organizers: { id: string; name: string }[] }) {
  const [state, action, pending] = useActionState(checkOrSubmitFeed, initialState);
  const [url, setUrl] = useState("");
  const previewMatches = state.preview && state.url && (state.url === url || state.url === url.replace(/^webcal:\/\//i, "https://"));

  return (
    <Card>
      <CardContent className="pt-5">
        <form action={action}>
          <h2 className="text-base font-semibold text-[#111111]">Feed hinterlegen</h2>
          <p className="mt-1 text-sm leading-6 text-[#4A4A4A]">
            Funktioniert mit Kalender-Abos (.ics / webcal, z. B. aus Google Kalender, Outlook oder deinem Ticketsystem), RSS-Feeds und Spielplan-Seiten
            mit schema.org-Event-Daten.
          </p>
          <div className="mt-5 grid gap-4 sm:grid-cols-[1fr_16rem]">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="feed-url">Adresse</Label>
              <Input required id="feed-url" name="url" placeholder="https://… oder webcal://…" value={url} onChange={(e) => setUrl(e.target.value)} />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="feed-organizer">Institution</Label>
              <select
                required
                id="feed-organizer"
                name="organizer_id"
                defaultValue={organizers.length === 1 ? organizers[0].id : ""}
                className="flex h-9 w-full rounded-lg border border-black/10 bg-white px-3 text-sm text-[#111111] transition focus-visible:border-[#2D2A6E] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2D2A6E]/25"
              >
                <option value="">Bitte wählen</option>
                {organizers.map((o) => (
                  <option key={o.id} value={o.id}>{o.name}</option>
                ))}
              </select>
            </div>
          </div>

          {state.error ? <p className="mt-4 rounded-lg bg-[#FDECEA] px-3 py-2 text-sm text-[#B42318]">{state.error}</p> : null}
          {state.submitted ? (
            <p className="mt-4 rounded-lg bg-[#EEF6F1] px-3 py-2 text-sm text-[#1F7A4D]">
              Danke! Die Redaktion prüft den Feed und schaltet ihn frei. Du bekommst die Termine danach automatisch unter „Meine Events“.
            </p>
          ) : null}

          {previewMatches && state.preview ? (
            <div className="mt-5 rounded-lg border border-[#111111]/[0.08] bg-[#FAFAFA] p-4">
              <p className="text-sm font-medium text-[#111111]">
                {TYPE_LABEL[state.preview.type]} erkannt · {state.preview.count} {state.preview.count === 1 ? "Termin" : "Termine"}
              </p>
              <ul className="mt-2 space-y-1 text-sm text-[#4A4A4A]">
                {state.preview.samples.map((s, i) => (
                  <li key={i} className="flex gap-3">
                    <span className="w-36 shrink-0 tabular-nums text-[#6B6B6B]">{s.start ?? "–"}</span>
                    <span className="truncate">{s.title}</span>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}

          <div className="mt-5 flex gap-2">
            {previewMatches ? (
              <Button type="submit" name="submit" value="1" disabled={pending}>
                {pending ? "Wird eingereicht …" : "Feed einreichen"}
              </Button>
            ) : (
              <Button type="submit" disabled={pending}>
                {pending ? "Wird geprüft …" : "Adresse prüfen"}
              </Button>
            )}
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
