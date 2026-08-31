"use client";

import { useState, useTransition } from "react";
import { requestPromotion } from "./actions";
import { PromotionEventPicker } from "./promotion-event-picker";
import { Label } from "@/components/organizer/ui/label";
import { Textarea } from "@/components/organizer/ui/input";
import { Button } from "@/components/organizer/ui/button";

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
    return <p className="text-sm text-[#726c78]">Es gibt aktuell keine kommenden veröffentlichten Events deiner eigenen oder beanspruchten Profile.</p>;
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
        <legend className="text-sm font-medium text-[#15131a]">Gewünschte Platzierung</legend>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          {PLACEMENTS.map((placement) => (
            <label
              key={placement.value}
              className="cursor-pointer rounded-xl border border-[#15131a]/10 bg-white p-4 text-sm transition hover:border-[#2D2A6E] has-[:checked]:border-[#2D2A6E] has-[:checked]:ring-1 has-[:checked]:ring-[#2D2A6E]"
            >
              <input required type="radio" name="placement" value={placement.value} className="mr-2 accent-[#2D2A6E]" />
              <span className="font-medium text-[#15131a]">{placement.label}</span>
              <span className="float-right text-xs font-semibold text-[#2D2A6E]">{priceLabels[placement.value] ?? placement.price}</span>
              <span className="mt-1 block text-xs leading-5 text-[#726c78]">{placement.description}</span>
            </label>
          ))}
        </div>
      </fieldset>
      <div>
        <Label htmlFor="promotion-requester-note">
          Nachricht an die Redaktion <span className="font-normal text-[#726c78]">(optional)</span>
        </Label>
        <Textarea id="promotion-requester-note" name="requester_note" maxLength={1000} rows={3} className="mt-1.5" placeholder="Warum passt diese Promotion zu deinem Event?" />
      </div>
      {error && <p className="text-sm text-[#a91551]">{error}</p>}
      {message && <p className="text-sm text-[#175f3c]">{message}</p>}
      <p className="text-xs leading-5 text-[#726c78]">Ablauf: Anfrage senden → Redaktion prüft die Platzierung → Zahlungslink erhalten → nach erfolgreicher Zahlung wird die Promotion aktiviert.</p>
      <Button disabled={pending}>{pending ? "Wird gesendet…" : "Promotion beantragen"}</Button>
    </form>
  );
}
