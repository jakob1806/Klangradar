"use client";

import { useActionState, useState, type FormEvent } from "react";
import { Field, Select, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { toMunichDatetimeLocal } from "@/lib/munich-time";
import { GenrePicker } from "@/app/(dashboard)/events/genre-picker";
import { VenuePicker } from "./venue-picker";
import { OrganizerPicker } from "./organizer-picker";
import { EventPreviewCard, type EventPreviewData } from "./event-preview-card";

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

// Muss zum Check-Constraint events_remaining_tickets_status_check passen
// (20260904000001_event_ticket_details.sql) — identisch zu event-form.tsx.
const TICKET_STATUS_OPTIONS = [
  { value: "", label: "— (unbekannt)" },
  { value: "available", label: "Verfügbar" },
  { value: "few_left", label: "Nur noch wenige" },
  { value: "sold_out", label: "Ausverkauft" },
  { value: "box_office_only", label: "Nur Abendkasse" },
];

export interface OrganizerEventFormValues {
  slug: string;
  title: string;
  subtitle: string | null;
  description_de: string | null;
  start_datetime: string | null;
  duration_minutes: number | null;
  has_intermission: boolean;
  venue_id: string;
  venue_name: string;
  venue_detail: string | null;
  organizer_id: string;
  ticket_url: string | null;
  price_min: number | null;
  price_max: number | null;
  is_free: boolean;
  remaining_tickets_status: string | null;
  doors_info: string | null;
  age_restriction: string | null;
  discount_info: string | null;
  presale_fee_info: string | null;
  genreIds: string[];
}

// Eigene Variante statt (dashboard)/events/event-form.tsx wiederzuverwenden:
// dort ist venue_id/organizer_id ein <select> über ALLE Zeilen und status
// frei wählbar — beides für Selbstbedienung falsch (siehe Plan). Kein
// status-Feld hier: die Server Action erzwingt bei Neuanlage immer "draft",
// bei Bearbeitung greift stattdessen der DB-Trigger
// events_organizer_status_guard (status bleibt unverändert, egal was
// gesendet wird).
export function OrganizerEventForm({
  action,
  initial,
  organizers,
  genres,
  initialImageUrl,
  organizerLocked = false,
  organizerLockedName,
}: {
  action: (formData: FormData) => Promise<{ error?: string }>;
  initial?: OrganizerEventFormValues;
  organizers: { id: string; name: string }[];
  genres: { id: string; label_de: string }[];
  initialImageUrl?: string | null;
  organizerLocked?: boolean;
  organizerLockedName?: string | null;
}) {
  const [slug, setSlug] = useState(initial?.slug ?? "");
  const [slugTouched, setSlugTouched] = useState(Boolean(initial));
  const [state, formAction] = useActionState(
    async (_previous: { error?: string }, formData: FormData) => action(formData),
    {},
  );
  const [venueName, setVenueName] = useState(initial?.venue_name ?? "");
  const [preview, setPreview] = useState<EventPreviewData>({
    title: initial?.title ?? "",
    subtitle: initial?.subtitle ?? "",
    startDatetime: toMunichDatetimeLocal(initial?.start_datetime ?? null),
    venueName: initial?.venue_name ?? "",
    doorsInfo: initial?.doors_info ?? "",
    isFree: initial?.is_free ?? false,
    priceMin: initial?.price_min != null ? String(initial.price_min) : "",
    priceMax: initial?.price_max != null ? String(initial.price_max) : "",
    imageUrl: initialImageUrl ?? null,
  });

  // Ein einziger onChange-Handler auf dem <form> statt jedes Feld
  // kontrolliert zu machen — nutzt React-Event-Bubbling, damit die
  // bestehenden unkontrollierten Inputs (defaultValue + useActionState)
  // unangetastet bleiben. venue_name kommt separat aus VenuePickers
  // onSelect, weil das sichtbare Venue-Suchfeld kein name-Attribut hat und
  // deshalb nicht in FormData landet.
  function handleFormChange(event: FormEvent<HTMLFormElement>) {
    const data = new FormData(event.currentTarget);
    setPreview({
      title: String(data.get("title") ?? ""),
      subtitle: String(data.get("subtitle") ?? ""),
      startDatetime: String(data.get("start_datetime") ?? ""),
      venueName,
      doorsInfo: String(data.get("doors_info") ?? ""),
      isFree: data.get("is_free") != null,
      priceMin: String(data.get("price_min") ?? ""),
      priceMax: String(data.get("price_max") ?? ""),
      imageUrl: initialImageUrl ?? null,
    });
  }

  return (
    <div className="grid grid-cols-1 gap-8 lg:grid-cols-[1fr_320px]">
    <form action={formAction} onChange={handleFormChange} className="flex max-w-2xl flex-col gap-4">
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

      {organizerLocked ? (
        <div className="rounded-xl bg-[#f1ede5] px-4 py-3">
          <input type="hidden" name="organizer_id" value={initial?.organizer_id ?? ""} />
          <p className="text-xs font-semibold text-[#5f5b56]">Veranstalter bleibt unverändert</p>
          <p className="mt-1 text-sm text-[#292825]">{organizerLockedName ?? "Bestehender Veranstalter"}</p>
        </div>
      ) : organizers.length > 1 ? (
        <OrganizerPicker organizers={organizers} initial={initial?.organizer_id} />
      ) : (
        <input type="hidden" name="organizer_id" value={initial?.organizer_id ?? organizers[0]?.id ?? ""} />
      )}

      <div className="grid grid-cols-2 gap-4">
        <Field label="Venue" required>
          <VenuePicker
            initial={initial ? { id: initial.venue_id, name: initial.venue_name } : undefined}
            onSelect={(venue) => {
              const name = venue?.name ?? "";
              setVenueName(name);
              setPreview((current) => ({ ...current, venueName: name }));
            }}
          />
        </Field>
        <Field label="Saal / Bühne">
          <TextInput name="venue_detail" placeholder="z. B. Probebühne" defaultValue={initial?.venue_detail ?? ""} />
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
          <TextInput name="doors_info" placeholder="z.B. Einlass 19:00 Uhr" defaultValue={initial?.doors_info ?? ""} />
        </Field>
        <Field label="Altersbeschränkung">
          <TextInput name="age_restriction" placeholder="z.B. ab 6 Jahren" defaultValue={initial?.age_restriction ?? ""} />
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

      {!initial && (
        <p className="text-xs text-neutral-400">
          Dein Event wird als Entwurf angelegt und erscheint erst nach redaktioneller Prüfung öffentlich.
        </p>
      )}
      {initial && (
        <p className="text-xs text-neutral-400">
          Änderungen an einem bereits veröffentlichten Event sind sofort sichtbar, ohne erneute Prüfung.
        </p>
      )}

      {state.error && (
        <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {state.error}
        </p>
      )}

      <div className="mt-2">
        <SubmitButton>{initial ? "Speichern" : "Event anlegen"}</SubmitButton>
      </div>
    </form>

    <div className="lg:sticky lg:top-6 lg:self-start">
      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-[#86868b]">Vorschau</p>
      <EventPreviewCard preview={preview} />
    </div>
    </div>
  );
}
