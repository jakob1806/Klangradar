"use client";

import { useState } from "react";
import { Field, TextArea, TextInput } from "@/components/form-fields";
import { ImageUploadField } from "@/components/image-upload-field";
import { SubmitButton } from "@/components/submit-button";
import { SocialLinksFields } from "@/components/social-links-fields";

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

export interface VenueFormValues {
  slug: string;
  name: string;
  description_de: string | null;
  address_street: string;
  address_zip: string;
  address_city: string;
  lat: number | null;
  lng: number | null;
  capacity: number | null;
  website_url: string | null;
  social_links: Record<string, string> | null;
  photo_url: string | null;
  city_id: string | null;
}

export interface CityOption {
  id: string;
  name_de: string;
  short_name_de: string | null;
}

export function VenueForm({
  action,
  initial,
  cities,
  affectedEventCount,
}: {
  action: (formData: FormData) => void;
  initial?: VenueFormValues;
  cities: CityOption[];
  /** Nur bei Bearbeiten gesetzt: Anzahl Events dieser Venue, die bei einem
   * Stadtwechsel automatisch mitziehen würden (Trigger
   * venues_cascade_city_to_events, siehe 20261031000002). */
  affectedEventCount?: number;
}) {
  const [slug, setSlug] = useState(initial?.slug ?? "");
  const [slugTouched, setSlugTouched] = useState(Boolean(initial));

  return (
    <form action={action} className="flex max-w-xl flex-col gap-4">
      <Field label="Name" required>
        <TextInput
          name="name"
          required
          defaultValue={initial?.name}
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

      <Field label="Beschreibung">
        <TextArea name="description_de" rows={3} defaultValue={initial?.description_de ?? ""} />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Straße & Hausnummer" required>
          <TextInput name="address_street" required defaultValue={initial?.address_street} />
        </Field>
        <Field label="PLZ" required>
          <TextInput name="address_zip" required defaultValue={initial?.address_zip} />
        </Field>
      </div>

      <Field label="Adresse (Ort, Freitext)" required>
        <TextInput name="address_city" required defaultValue={initial?.address_city ?? "München"} />
      </Field>

      <Field label="Konzertregion" required>
        <select
          name="city_id"
          required
          defaultValue={initial?.city_id ?? ""}
          className="w-full rounded-lg border border-neutral-300 bg-white px-3 py-2 text-sm"
        >
          <option value="" disabled>
            Konzertregion wählen …
          </option>
          {cities.map((c) => (
            <option key={c.id} value={c.id}>
              {c.short_name_de ?? c.name_de}
            </option>
          ))}
        </select>
        <p className="mt-1 text-xs text-neutral-500">
          Steuert, in welcher Stadt diese Venue in Suche/Karte/Feed erscheint — unabhängig vom Adressfeld oben
          (z.B. Kronberg im Taunus bleibt als Adresse stehen, Konzertregion kann trotzdem Frankfurt sein).
        </p>
        {initial && affectedEventCount !== undefined && affectedEventCount > 0 && (
          <p className="mt-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            Achtung: {affectedEventCount} Veranstaltung{affectedEventCount === 1 ? "" : "en"} dieser Venue{" "}
            {affectedEventCount === 1 ? "zieht" : "ziehen"} bei einem Stadtwechsel automatisch mit um.
          </p>
        )}
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Breitengrad (lat)" required>
          <TextInput
            name="lat"
            type="number"
            step="any"
            required
            defaultValue={initial?.lat ?? ""}
            placeholder="48.1351"
          />
        </Field>
        <Field label="Längengrad (lng)" required>
          <TextInput
            name="lng"
            type="number"
            step="any"
            required
            defaultValue={initial?.lng ?? ""}
            placeholder="11.5820"
          />
        </Field>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Kapazität">
          <TextInput name="capacity" type="number" defaultValue={initial?.capacity ?? ""} />
        </Field>
        <Field label="Website">
          <TextInput name="website_url" type="url" defaultValue={initial?.website_url ?? ""} />
        </Field>
      </div>

      <ImageUploadField name="photo_url" initialUrl={initial?.photo_url} entityType="venues" shape="rounded" label="Foto" />

      <SocialLinksFields initial={initial?.social_links} />

      <div className="mt-2">
        <SubmitButton>{initial ? "Speichern" : "Venue anlegen"}</SubmitButton>
      </div>
    </form>
  );
}
