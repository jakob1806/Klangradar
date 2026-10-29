"use client";

import { useEffect, useState, useTransition } from "react";
import { quotePromotion, requestPromotion } from "./actions";
import { PromotionQuotePanel } from "./promotion-quote-panel";
import { TARGET_AUDIENCES, type PromotionQuote } from "@/lib/promotion-quote";
import { Input } from "@/components/organizer/ui/input";
import { PromotionEventPicker } from "./promotion-event-picker";
import { PlacementPreview } from "./placement-preview";
import { Label } from "@/components/organizer/ui/label";
import { Textarea } from "@/components/organizer/ui/input";
import { Button } from "@/components/organizer/ui/button";

type EventOption = { id: string; title: string; startLabel: string; concertDay: string; venueName: string | null; imageUrl: string | null; sourceLabel: string };

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
  const [selectedEvent, setSelectedEvent] = useState<EventOption | null>(null);
  const [chosenPlacement, setChosenPlacement] = useState<string>("");
  // Erweiterung (Claude Code, 29.10.2026): Laufzeit, Budgets und Zielgruppe
  // mit Live-Angebot aus promotion_quote.
  const [runStart, setRunStart] = useState("");
  const [runEnd, setRunEnd] = useState("");
  const [dailyCap, setDailyCap] = useState("");
  const [totalBudget, setTotalBudget] = useState("");
  const [quote, setQuote] = useState<PromotionQuote | null>(null);
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [quoting, startQuote] = useTransition();
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Berlin" }).format(new Date());
  const isPush = chosenPlacement === "push";

  useEffect(() => {
    if (!selectedEvent || !chosenPlacement) return;
    const timer = setTimeout(() => {
      startQuote(async () => {
        const result = await quotePromotion({ eventId: selectedEvent.id, placement: chosenPlacement, start: runStart, end: isPush ? "" : runEnd, dailyCap: isPush ? "" : dailyCap, totalBudget: isPush ? "" : totalBudget });
        setQuote(result.quote ?? null);
        setQuoteError(result.error ?? null);
      });
    }, 350);
    return () => clearTimeout(timer);
  }, [selectedEvent, chosenPlacement, runStart, runEnd, dailyCap, totalBudget, isPush]);

  if (!events.length) {
    return <p className="text-sm text-[#6B6B6B]">Es gibt aktuell keine kommenden veröffentlichten Events deiner eigenen oder beanspruchten Profile.</p>;
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
            setMessage(result.autoApproved ? "Standard-Platzierung sofort freigegeben – du kannst unten direkt bezahlen." : "Deine Anfrage wurde an die Redaktion gesendet.");
            (document.getElementById("promotion-request-form") as HTMLFormElement | null)?.reset();
            setChosenPlacement("");
            setSelectedEvent(null);
            setRunStart("");
            setRunEnd("");
            setDailyCap("");
            setTotalBudget("");
            setQuote(null);
          } catch (cause) {
            setError(cause instanceof Error ? cause.message : "Die Anfrage konnte nicht gesendet werden.");
          }
        });
      }}
      id="promotion-request-form"
    >
      <PromotionEventPicker events={events} onSelect={(picked) => setSelectedEvent(picked ? events.find((event) => event.id === picked.id) ?? null : null)} />
      <fieldset>
        <legend className="text-sm font-medium text-[#111111]">Gewünschte Platzierung</legend>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          {PLACEMENTS.map((placement) => (
            <label
              key={placement.value}
              className="cursor-pointer rounded-xl border border-[#111111]/10 bg-white p-4 text-sm transition hover:border-[#2D2A6E] has-[:checked]:border-[#2D2A6E] has-[:checked]:ring-1 has-[:checked]:ring-[#2D2A6E]"
            >
              <input required type="radio" name="placement" value={placement.value} checked={chosenPlacement === placement.value} onChange={() => setChosenPlacement(placement.value)} className="mr-2 accent-[#2D2A6E]" />
              <span className="font-medium text-[#111111]">{placement.label}</span>
              <span className="float-right text-xs font-semibold text-[#2D2A6E]">{priceLabels[placement.value] ?? placement.price}</span>
              <span className="mt-1 block text-xs leading-5 text-[#6B6B6B]">{placement.description}</span>
            </label>
          ))}
        </div>
      </fieldset>
      <section className="rounded-2xl border border-[#111111]/[0.07] bg-[#FAFAFA] p-5">
        {chosenPlacement ? (
          <PlacementPreview placement={chosenPlacement} event={selectedEvent} />
        ) : (
          <p className="text-center text-sm text-[#6B6B6B]">
            Wähle eine Platzierung, um zu sehen, an welcher Stelle der App dein Event angezeigt wird.
          </p>
        )}
        {chosenPlacement && !selectedEvent && (
          <p className="mt-3 text-center text-xs text-[#6B6B6B]">Wähle oben ein Event, dann siehst du es direkt in der Vorschau.</p>
        )}
      </section>
      <fieldset className="grid gap-4 rounded-2xl border border-[#111111]/[0.07] p-5 sm:grid-cols-2">
        <legend className="px-1 text-sm font-medium text-[#111111]">{isPush ? "Versand" : "Laufzeit & Budget"}</legend>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="promotion-run-start">{isPush ? "Versanddatum" : "Start"}</Label>
          <Input id="promotion-run-start" name="run_start" type="date" min={today} max={selectedEvent?.concertDay} value={runStart} onChange={(event) => setRunStart(event.target.value)} />
          <span className="text-xs text-[#6B6B6B]">Leer = ab Zahlungseingang</span>
        </div>
        {!isPush && (
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="promotion-run-end">Ende</Label>
            <Input id="promotion-run-end" name="run_end" type="date" min={runStart || today} max={selectedEvent?.concertDay} value={runEnd} onChange={(event) => setRunEnd(event.target.value)} />
            <span className="text-xs text-[#6B6B6B]">Leer = bis zum Konzerttag</span>
          </div>
        )}
        {!isPush && (
          <>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="promotion-daily-cap">Tagesbudget (optional)</Label>
              <Input id="promotion-daily-cap" name="daily_cap" inputMode="decimal" placeholder="z. B. 10 €" value={dailyCap} onChange={(event) => setDailyCap(event.target.value)} />
              <span className="text-xs text-[#6B6B6B]">Tage mit höherem Tagespreis werden ausgelassen.</span>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="promotion-total-budget">Gesamtbudget (optional)</Label>
              <Input id="promotion-total-budget" name="total_budget" inputMode="decimal" placeholder="z. B. 150 €" value={totalBudget} onChange={(event) => setTotalBudget(event.target.value)} />
              <span className="text-xs text-[#6B6B6B]">Es zählen die Tage direkt vor dem Konzert, bis das Budget erreicht ist.</span>
            </div>
          </>
        )}
      </fieldset>
      <fieldset>
        <legend className="text-sm font-medium text-[#111111]">Zielgruppe</legend>
        <p className="mt-0.5 text-xs text-[#6B6B6B]">Ohne Auswahl sehen alle in der Stadt des Konzerts die Promotion. Mit Auswahl nur Personen, auf die mindestens ein Punkt zutrifft.</p>
        <div className="mt-2 grid gap-2 sm:grid-cols-3">
          {TARGET_AUDIENCES.map((audience) => (
            <label
              key={audience.value}
              className="cursor-pointer rounded-xl border border-[#111111]/10 bg-white p-3 text-sm transition hover:border-[#2D2A6E] has-[:checked]:border-[#2D2A6E] has-[:checked]:ring-1 has-[:checked]:ring-[#2D2A6E]"
            >
              <input type="checkbox" name="target_audiences" value={audience.value} className="mr-2 accent-[#2D2A6E]" />
              <span className="font-medium text-[#111111]">{audience.label}</span>
              <span className="mt-1 block text-xs leading-5 text-[#6B6B6B]">{audience.description}</span>
            </label>
          ))}
        </div>
      </fieldset>
      {selectedEvent && chosenPlacement && (
        <PromotionQuotePanel quote={quote} error={quoteError} loading={quoting} flatPriceLabel={priceLabels[chosenPlacement] ?? null} />
      )}
      <div>
        <Label htmlFor="promotion-requester-note">
          Nachricht an die Redaktion <span className="font-normal text-[#6B6B6B]">(optional)</span>
        </Label>
        <Textarea id="promotion-requester-note" name="requester_note" maxLength={1000} rows={3} className="mt-1.5" placeholder="Warum passt diese Promotion zu deinem Event?" />
      </div>
      {error && <p className="text-sm text-[#a91551]">{error}</p>}
      {message && <p className="text-sm text-[#175f3c]">{message}</p>}
      <div className="rounded-xl bg-[#ECEBFA] px-4 py-3 text-[13px] leading-5 text-[#2D2A6E]">
        <strong>Laufzeit:</strong> Ohne eigene Auswahl läuft die Promotion ab Zahlungseingang bis zum Konzerttag{selectedEvent ? ` (${selectedEvent.startLabel})` : ""}. Tage vor dem Zahlungseingang werden nicht berechnet.
      </div>
      <p className="text-xs leading-5 text-[#6B6B6B]">Ablauf: Anfrage senden → Redaktion prüft die Platzierung (du bekommst eine E-Mail) → Zahlung → die Promotion ist sofort live. Nach dem Konzerttag erhältst du eine Auswertung.</p>
      <Button disabled={pending}>{pending ? "Wird gesendet…" : "Promotion beantragen"}</Button>
    </form>
  );
}
