"use client";

import { useState, useTransition } from "react";
import { requestPromotion } from "./actions";
import { PromotionEventPicker } from "./promotion-event-picker";

type EventOption = { id: string; title: string; startLabel: string; venueName: string | null; imageUrl: string | null; sourceLabel: string };

const PLACEMENTS = [
  { value: "standard", label: "Standard", price: "Preis im Checkout", description: "Hervorgehobene Darstellung in den Event-Listen." },
  { value: "featured", label: "Featured", price: "Preis im Checkout", description: "Besonders prominente Platzierung im Entdecken-Bereich." },
  { value: "local_spotlight", label: "Local Spotlight", price: "Preis im Checkout", description: "Lokale Empfehlung für die Veranstaltungsstadt." },
  { value: "homepage_feature", label: "Homepage Feature", price: "Preis im Checkout", description: "Redaktionell kuratierter Auftritt auf der Startseite." },
  { value: "push", label: "Push-Anfrage", price: "Preis im Checkout", description: "Redaktionell freizugebende Benachrichtigung; kein automatischer Versand." },
] as const;

export function PromotionRequestForm({ events, priceLabels }: { events: EventOption[]; priceLabels: Record<string, string> }) {
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!events.length) {
    return <p className="text-sm text-[#86868b]">Es gibt aktuell keine kommenden veröffentlichten Events deiner eigenen oder beanspruchten Profile.</p>;
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
      <PromotionEventPicker events={events} />
      <fieldset>
        <legend className="text-sm font-medium text-[#1d1d1f]">Gewünschte Platzierung</legend>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          {PLACEMENTS.map((placement) => (
            <label key={placement.value} className="cursor-pointer rounded-xl border border-black/10 bg-white p-4 text-sm transition hover:border-[#0071e3] has-[:checked]:border-[#0071e3] has-[:checked]:ring-1 has-[:checked]:ring-[#0071e3]">
              <input required type="radio" name="placement" value={placement.value} className="mr-2 accent-[#0071e3]" />
              <span className="font-medium text-[#1d1d1f]">{placement.label}</span>
              <span className="float-right text-xs font-semibold text-[#0071e3]">{priceLabels[placement.value] ?? placement.price}</span>
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
      <p className="text-xs leading-5 text-[#86868b]">Ablauf: Anfrage senden → Redaktion prüft die Platzierung → Zahlungslink erhalten → nach erfolgreicher Zahlung wird die Promotion aktiviert.</p>
      <button disabled={pending} className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#0077ed] disabled:opacity-50">
        {pending ? "Wird gesendet…" : "Promotion beantragen"}
      </button>
    </form>
  );
}
