"use client";

import { useState } from "react";
import { TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { DeleteButton } from "@/components/delete-button";
import { addTicketLink, removeTicketLink } from "./ticket-link-actions";

export interface TicketLinkRow {
  url: string;
  price_min: number | null;
  price_max: number | null;
  currency: string;
  is_primary: boolean;
  is_broken: boolean;
  last_checked_at: string | null;
  availability_status?: string | null;
  discount_categories?: string[];
  discount_notes?: string | null;
  price_updated_at?: string | null;
  ticket_providers: { name: string } | null;
}

/** Ticket Intelligence: "Mehrere Ticketanbieter pro Event unterstützen" —
 * die primäre Zeile (aus events.ticket_url abgeleitet) wird oben im
 * Eventformular gepflegt und hier nur informativ mitangezeigt; zusätzliche
 * Anbieter lassen sich hier ergänzen/entfernen. */
export function TicketProviderManager({ eventId, links }: { eventId: string; links: TicketLinkRow[] }) {
  const [error, setError] = useState<string | null>(null);

  async function action(formData: FormData) {
    setError(null);
    const result = await addTicketLink(eventId, formData);
    if (result.error) setError(result.error);
  }

  return (
    <div className="mt-8 max-w-xl border-t border-neutral-200 pt-6">
      <h2 className="text-sm font-semibold text-neutral-900">Ticketanbieter</h2>
      <p className="mt-1 text-xs text-neutral-400">
        Der primäre Anbieter kommt automatisch aus dem „Ticket-Link“-Feld oben. Weitere Verkaufsstellen (z. B. ein
        zweiter Vorverkauf) lassen sich hier ergänzen.
      </p>

      {links.length > 0 && (
        <ul className="mt-3 flex flex-col gap-2">
          {links.map((link) => (
            <li
              key={link.url}
              className="flex items-center justify-between gap-3 rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-medium text-neutral-900">{link.ticket_providers?.name ?? link.url}</span>
                  {link.is_primary && (
                    <span className="rounded bg-neutral-100 px-1.5 py-0.5 text-[10px] font-medium uppercase text-neutral-500">
                      primär
                    </span>
                  )}
                  {link.is_broken && (
                    <span
                      className="rounded bg-red-50 px-1.5 py-0.5 text-[10px] font-medium uppercase text-red-700"
                      title="Automatische Prüfung meldet Seite nicht mehr erreichbar (404/410) — bitte manuell nachschauen."
                    >
                      Link defekt
                    </span>
                  )}
                </div>
                <a
                  href={link.url}
                  target="_blank"
                  rel="noreferrer"
                  className="block truncate text-xs text-neutral-500 hover:underline"
                >
                  {link.url}
                </a>
                {(link.price_min != null || link.price_max != null) && (
                  <span className="text-xs text-neutral-500">
                    {link.price_min != null && link.price_max != null && link.price_min !== link.price_max
                      ? `${link.price_min}–${link.price_max} ${link.currency}`
                      : `ab ${link.price_min ?? link.price_max} ${link.currency}`}
                  </span>
                )}
                <div className="mt-1 flex flex-wrap gap-1 text-[10px] text-neutral-500">
                  {link.availability_status && <span>{link.availability_status}</span>}
                  {link.discount_categories?.map((discount) => <span key={discount} className="rounded bg-blue-50 px-1.5 py-0.5 text-blue-700">{discount}</span>)}
                  {link.price_updated_at && <span>Preisstand {new Date(link.price_updated_at).toLocaleString("de-DE")}</span>}
                </div>
              </div>
              {!link.is_primary && (
                <DeleteButton
                  action={removeTicketLink.bind(null, eventId, link.url)}
                  confirmMessage="Diesen Ticketanbieter entfernen?"
                />
              )}
            </li>
          ))}
        </ul>
      )}

      <form action={action} className="mt-4 flex flex-col gap-3">
        <div className="grid grid-cols-3 gap-3">
          <div className="col-span-3">
            <TextInput name="url" type="url" placeholder="https://…" required className="w-full" />
          </div>
          <TextInput name="price_min" type="number" step="0.01" placeholder="Preis von (€)" className="w-full" />
          <TextInput name="price_max" type="number" step="0.01" placeholder="Preis bis (€)" className="w-full" />
          <select name="availability_status" defaultValue="unknown" className="rounded-lg border border-neutral-300 bg-white px-3 py-2 text-sm">
            <option value="unknown">Verfügbarkeit unbekannt</option><option value="available">Verfügbar</option>
            <option value="few_left">Wenige Tickets</option><option value="sold_out">Ausverkauft</option><option value="box_office_only">Nur Abendkasse</option>
          </select>
          <div className="col-span-3 flex flex-wrap gap-4 text-sm">
            {[['u30','U30'],['student','Studierende'],['schueler','Schüler:innen']].map(([value,label]) => <label key={value} className="flex items-center gap-1"><input type="checkbox" name="discount_categories" value={value}/>{label}</label>)}
          </div>
          <div className="col-span-3"><TextInput name="discount_notes" placeholder="Hinweise/Nachweis für Ermäßigungen" className="w-full" /></div>
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <div>
          <SubmitButton pendingLabel="Ergänze…">Anbieter ergänzen</SubmitButton>
        </div>
      </form>
    </div>
  );
}
