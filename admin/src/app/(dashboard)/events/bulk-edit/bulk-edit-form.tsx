"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Select, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { bulkUpdateEvents } from "../actions";

const STATUS_OPTIONS = [
  { value: "scheduled", label: "Geplant" },
  { value: "sold_out", label: "Ausverkauft" },
  { value: "cancelled", label: "Abgesagt" },
  { value: "postponed", label: "Verschoben" },
  { value: "draft", label: "Entwurf (nicht öffentlich)" },
];

const TICKET_STATUS_OPTIONS = [
  { value: "", label: "— (unbekannt)" },
  { value: "available", label: "Verfügbar" },
  { value: "few_left", label: "Nur noch wenige" },
  { value: "sold_out", label: "Ausverkauft" },
  { value: "box_office_only", label: "Nur Abendkasse" },
];

/** Jede Zeile hat eine eigene "Übernehmen"-Checkbox statt eines einzelnen
 * Speichern-für-alles: ein leeres Feld ist sonst nicht eindeutig "nicht
 * ändern" vs. "auf leer setzen", und i.d.R. soll nur EIN oder zwei Felder
 * (z.B. Status, Veranstalter) über mehrere ausgewählte Events hinweg
 * gleichgesetzt werden, nicht das ganze Formular. */
function ApplyRow({
  field,
  label,
  children,
}: {
  field: string;
  label: string;
  children: React.ReactNode;
}) {
  const [apply, setApply] = useState(false);
  return (
    <div className={`flex items-start gap-3 rounded-md border p-3 ${apply ? "border-neutral-400 bg-neutral-50" : "border-neutral-200"}`}>
      <input
        type="checkbox"
        name={`apply_${field}`}
        checked={apply}
        onChange={(e) => setApply(e.target.checked)}
        className="mt-2.5"
      />
      <div className="flex-1">
        <span className="text-xs font-medium text-neutral-600">{label}</span>
        <div className={apply ? "" : "pointer-events-none opacity-40"}>{children}</div>
      </div>
    </div>
  );
}

export function BulkEditForm({
  eventIds,
  venues,
  organizers,
  genres,
}: {
  eventIds: string[];
  venues: { id: string; name: string }[];
  organizers: { id: string; name: string }[];
  genres: { id: string; label_de: string }[];
}) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function action(formData: FormData) {
    setError(null);
    setMessage(null);
    const result = await bulkUpdateEvents(eventIds, formData);
    if (result.error) {
      setError(result.error);
      return;
    }
    setMessage(`${result.updated} Veranstaltung${result.updated === 1 ? "" : "en"} aktualisiert.`);
    router.refresh();
  }

  return (
    <form action={action} className="flex max-w-2xl flex-col gap-3">
      <ApplyRow field="venue_id" label="Venue">
        <Select name="venue_id" defaultValue="">
          <option value="" disabled>
            Bitte wählen…
          </option>
          {venues.map((v) => (
            <option key={v.id} value={v.id}>
              {v.name}
            </option>
          ))}
        </Select>
      </ApplyRow>

      <ApplyRow field="organizer_id" label="Veranstalter">
        <Select name="organizer_id" defaultValue="">
          <option value="">—</option>
          {organizers.map((o) => (
            <option key={o.id} value={o.id}>
              {o.name}
            </option>
          ))}
        </Select>
      </ApplyRow>

      <ApplyRow field="genre_ids" label="Genres (ersetzt die bisherige Auswahl je Event)">
        <div className="flex flex-wrap gap-x-4 gap-y-2 rounded-md border border-neutral-300 bg-white px-3 py-2.5">
          {genres.map((g) => (
            <label key={g.id} className="flex items-center gap-1.5 text-sm text-neutral-700">
              <input type="checkbox" name="genre_ids" value={g.id} />
              {g.label_de}
            </label>
          ))}
        </div>
      </ApplyRow>

      <ApplyRow field="status" label="Status">
        <Select name="status" defaultValue="scheduled">
          {STATUS_OPTIONS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </Select>
      </ApplyRow>

      <div className="grid grid-cols-2 gap-3">
        <ApplyRow field="price_min" label="Preis von (€)">
          <TextInput name="price_min" type="number" step="0.01" />
        </ApplyRow>
        <ApplyRow field="price_max" label="Preis bis (€)">
          <TextInput name="price_max" type="number" step="0.01" />
        </ApplyRow>
      </div>

      <ApplyRow field="is_free" label="Kostenlos">
        <label className="flex items-center gap-2 text-sm text-neutral-700">
          <input type="checkbox" name="is_free" />
          Als kostenlos markieren
        </label>
      </ApplyRow>

      <ApplyRow field="ticket_url" label="Ticket-Link">
        <TextInput name="ticket_url" type="url" />
      </ApplyRow>

      <ApplyRow field="remaining_tickets_status" label="Ticket-Status">
        <Select name="remaining_tickets_status" defaultValue="">
          {TICKET_STATUS_OPTIONS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </Select>
      </ApplyRow>

      <div className="grid grid-cols-2 gap-3">
        <ApplyRow field="doors_info" label="Einlass">
          <TextInput name="doors_info" placeholder="z.B. Einlass 19:00 Uhr" />
        </ApplyRow>
        <ApplyRow field="age_restriction" label="Altersbeschränkung">
          <TextInput name="age_restriction" placeholder="z.B. ab 6 Jahren" />
        </ApplyRow>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <ApplyRow field="discount_info" label="Ermäßigung">
          <TextInput name="discount_info" placeholder="z.B. Schüler/Studierende 50%" />
        </ApplyRow>
        <ApplyRow field="presale_fee_info" label="Vorverkaufsgebühr">
          <TextInput name="presale_fee_info" placeholder="z.B. zzgl. VVK-Gebühr" />
        </ApplyRow>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-emerald-700">{message}</p>}

      <div className="mt-2">
        <SubmitButton pendingLabel="Wende an…">
          Auf {eventIds.length} Veranstaltung{eventIds.length === 1 ? "" : "en"} anwenden
        </SubmitButton>
      </div>
    </form>
  );
}
