"use client";

import { useState, useTransition } from "react";
import { requestPromotion } from "./actions";

type EventOption = { id: string; title: string; startLabel: string };

const PLACEMENTS = [
  { value: "standard", label: "Standard", description: "Hervorgehobene Darstellung in den Event-Listen." },
  { value: "featured", label: "Featured", description: "Besonders prominente Platzierung im Entdecken-Bereich." },
  { value: "local_spotlight", label: "Local Spotlight", description: "Lokale Empfehlung für die Veranstaltungsstadt." },
  { value: "homepage_feature", label: "Homepage Feature", description: "Redaktionell kuratierter Auftritt auf der Startseite." },
  { value: "push", label: "Push-Anfrage", description: "Redaktionell freizugebende Benachrichtigung; kein automatischer Versand." },
] as const;

export function PromotionRequestForm({ events }: { events: EventOption[] }) {
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!events.length) {
    return <p className="text-sm text-[#86868b]">Sobald ein kommendes Event veröffentlicht ist, kannst du dafür eine Promotion beantragen.</p>;
  }

  return (
    <form
      className="space-y-4"
      action={(formData) => {
        setMessage(null);
        setError(null);
        startTransition(async () => {
          try {
            const result = await requestPromotion(formData);
            if (result.error) {
              setError(result.error);
              return;
            }
            setMessage("Deine Anfrage wurde an die Redaktion gesendet.");
            (document.getElementById("promotion-request-form") as HTMLFormElement | null)?.reset();
          } catch (cause) {
            setError(cause instanceof Error ? cause.message : "Die Anfrage konnte nicht gesendet werden.");
          }
        });
      }}
      id="promotion-request-form"
    >
      <label className="block text-sm font-medium text-[#1d1d1f]">
        Event
        <select name="event_id" required className="mt-1.5 w-full rounded-lg border border-black/10 bg-white px-3 py-2 text-sm">
          <option value="">Bitte wählen</option>
          {events.map((event) => <option key={event.id} value={event.id}>{event.title} · {event.startLabel}</option>)}
        </select>
      </label>
      <fieldset>
        <legend className="text-sm font-medium text-[#1d1d1f]">Gewünschte Platzierung</legend>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          {PLACEMENTS.map((placement) => (
            <label key={placement.value} className="cursor-pointer rounded-lg border border-black/10 bg-white p-3 text-sm hover:border-[#0071e3]">
              <input required type="radio" name="placement" value={placement.value} className="mr-2 accent-[#0071e3]" />
              <span className="font-medium text-[#1d1d1f]">{placement.label}</span>
              <span className="mt-1 block text-xs leading-5 text-[#86868b]">{placement.description}</span>
            </label>
          ))}
        </div>
      </fieldset>
      <label className="block text-sm font-medium text-[#1d1d1f]">
        Nachricht an die Redaktion <span className="font-normal text-[#86868b]">(optional)</span>
        <textarea name="requester_note" maxLength={1000} rows={3} className="mt-1.5 w-full rounded-lg border border-black/10 bg-white px-3 py-2 text-sm" placeholder="Warum passt diese Promotion zu deinem Event?" />
      </label>
      {error && <p className="text-sm text-red-700">{error}</p>}
      {message && <p className="text-sm text-emerald-700">{message}</p>}
      <button disabled={pending} className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#0077ed] disabled:opacity-50">
        {pending ? "Wird gesendet…" : "Promotion beantragen"}
      </button>
    </form>
  );
}
