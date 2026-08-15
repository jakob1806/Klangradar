"use client";

import { useState } from "react";
import { Field, Select, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { toMunichDatetimeLocal } from "@/lib/munich-time";
import { GenrePicker } from "./genre-picker";

function slugify(value: string) {
  return value
    .toLowerCase()
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

const STATUS_OPTIONS = [
  { value: "scheduled", label: "Geplant" },
  { value: "sold_out", label: "Ausverkauft" },
  { value: "cancelled", label: "Abgesagt" },
  { value: "postponed", label: "Verschoben" },
  { value: "draft", label: "Entwurf (nicht öffentlich)" },
];

// Muss zum Check-Constraint events_remaining_tickets_status_check passen
// (20260904000001_event_ticket_details.sql).
const TICKET_STATUS_OPTIONS = [
  { value: "", label: "— (unbekannt)" },
  { value: "available", label: "Verfügbar" },
  { value: "few_left", label: "Nur noch wenige" },
  { value: "sold_out", label: "Ausverkauft" },
  { value: "box_office_only", label: "Nur Abendkasse" },
];

export interface EventFormValues {
  slug: string;
  title: string;
  subtitle: string | null;
  description_de: string | null;
  start_datetime: string | null;
  duration_minutes: number | null;
  has_intermission: boolean;
  venue_id: string;
  organizer_id: string | null;
  ticket_url: string | null;
  price_min: number | null;
  price_max: number | null;
  is_free: boolean;
  remaining_tickets_status: string | null;
  doors_info: string | null;
  age_restriction: string | null;
  discount_info: string | null;
  presale_fee_info: string | null;
  status: string;
  genreIds: string[];
}

export function EventForm({
  action,
  initial,
  venues,
  organizers,
  genres,
}: {
  action: (formData: FormData) => void;
  initial?: EventFormValues;
  venues: { id: string; name: string }[];
  organizers: { id: string; name: string }[];
  genres: { id: string; label_de: string }[];
}) {
  const [slug, setSlug] = useState(initial?.slug ?? "");
  const [slugTouched, setSlugTouched] = useState(Boolean(initial));

  return (
    <form action={action} className="flex max-w-2xl flex-col gap-4">
      <Field label="Titel" required>
        <TextInput
          name="title"
          required
          defaultValue={initial?.title}
          onChange={(e) => {
            if (!slugTouched) setSlug(slugify(e.target.value));
          }}
        />
      </Field>

      <Field label="Slug (URL)" required>
        <TextInput
          name="slug"
          required
          value={slug}
          onChange={(e) => {
            setSlugTouched(true);
            setSlug(e.target.value);
          }}
        />
      </Field>

      <Field label="Untertitel">
        <TextInput name="subtitle" defaultValue={initial?.subtitle ?? ""} />
      </Field>

      <Field label="Beschreibung">
        <TextArea name="description_de" rows={3} defaultValue={initial?.description_de ?? ""} />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Beginn" required>
          <TextInput
            name="start_datetime"
            type="datetime-local"
            required
            defaultValue={toMunichDatetimeLocal(initial?.start_datetime ?? null)}
          />
        </Field>
        <Field label="Dauer (Minuten)">
          <TextInput name="duration_minutes" type="number" defaultValue={initial?.duration_minutes ?? ""} />
        </Field>
      </div>

      <label className="flex items-center gap-2 text-sm text-neutral-700">
        <input type="checkbox" name="has_intermission" defaultChecked={initial?.has_intermission} />
        Mit Pause
      </label>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Venue" required>
          <Select name="venue_id" required defaultValue={initial?.venue_id ?? ""}>
            <option value="" disabled>
              Bitte wählen…
            </option>
            {venues.map((v) => (
              <option key={v.id} value={v.id}>
                {v.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Veranstalter">
          <Select name="organizer_id" defaultValue={initial?.organizer_id ?? ""}>
            <option value="">—</option>
            {organizers.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
          </Select>
        </Field>
      </div>

      <Field label="Genres">
        <GenrePicker genres={genres} initialIds={initial?.genreIds} />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Preis von (€)">
          <TextInput name="price_min" type="number" step="0.01" defaultValue={initial?.price_min ?? ""} />
        </Field>
        <Field label="Preis bis (€)">
          <TextInput name="price_max" type="number" step="0.01" defaultValue={initial?.price_max ?? ""} />
        </Field>
      </div>

      <label className="flex items-center gap-2 text-sm text-neutral-700">
        <input type="checkbox" name="is_free" defaultChecked={initial?.is_free} />
        Kostenlos
      </label>

      <Field label="Ticket-Link">
        <TextInput name="ticket_url" type="url" defaultValue={initial?.ticket_url ?? ""} />
      </Field>

      <Field label="Ticket-Status">
        <Select name="remaining_tickets_status" defaultValue={initial?.remaining_tickets_status ?? ""}>
          {TICKET_STATUS_OPTIONS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </Select>
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Einlass">
          <TextInput
            name="doors_info"
            placeholder="z.B. Einlass 19:00 Uhr"
            defaultValue={initial?.doors_info ?? ""}
          />
        </Field>
        <Field label="Altersbeschränkung">
          <TextInput
            name="age_restriction"
            placeholder="z.B. ab 6 Jahren"
            defaultValue={initial?.age_restriction ?? ""}
          />
        </Field>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Ermäßigung">
          <TextInput
            name="discount_info"
            placeholder="z.B. Schüler/Studierende 50%"
            defaultValue={initial?.discount_info ?? ""}
          />
        </Field>
        <Field label="Vorverkaufsgebühr">
          <TextInput
            name="presale_fee_info"
            placeholder="z.B. zzgl. VVK-Gebühr"
            defaultValue={initial?.presale_fee_info ?? ""}
          />
        </Field>
      </div>

      <Field label="Status" required>
        <Select name="status" required defaultValue={initial?.status ?? "scheduled"}>
          {STATUS_OPTIONS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </Select>
      </Field>

      {!initial && (
        <p className="text-xs text-neutral-400">
          Programm und Mitwirkende lassen sich nach dem Anlegen auf der Bearbeiten-Seite ergänzen.
        </p>
      )}

      <div className="mt-2">
        <SubmitButton>{initial ? "Speichern" : "Event anlegen"}</SubmitButton>
      </div>
    </form>
  );
}
