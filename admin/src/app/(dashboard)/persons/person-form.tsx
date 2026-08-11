"use client";

import { useState } from "react";
import { Field, Select, TextArea, TextInput } from "@/components/form-fields";
import { ImageUploadField } from "@/components/image-upload-field";
import { AvatarCropButton } from "@/components/entity-gallery/avatar-crop-button";
import type { CropRect } from "@/components/entity-gallery/crop-math";
import { SubmitButton } from "@/components/submit-button";

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

const ROLE_OPTIONS = [
  { value: "komponist", label: "Komponist:in" },
  { value: "dirigent", label: "Dirigent:in" },
  { value: "solist", label: "Solist:in" },
  { value: "chorleiter", label: "Chorleiter:in" },
  { value: "moderator", label: "Moderator:in" },
];

export interface PersonFormValues {
  slug: string;
  first_name: string;
  middle_name: string | null;
  last_name: string;
  roles: string[];
  instrument: string | null;
  nationality: string | null;
  birth_date: string | null;
  death_date: string | null;
  is_deceased: boolean;
  biography_de: string | null;
  website_url: string | null;
  photo_url: string | null;
  avatar_crop_x: number | null;
  avatar_crop_y: number | null;
  avatar_crop_width: number | null;
  avatar_crop_height: number | null;
  member_of_ensemble_id: string | null;
  is_verified: boolean;
}

export function PersonForm({
  action,
  initial,
  ensembles,
  personId,
}: {
  action: (formData: FormData) => void;
  initial?: PersonFormValues;
  /** Für die "Gehört zu Ensemble"-Auswahl, z. B. "Solist(en) des Tölzer
   * Knabenchors" gehört zum Ensemble "Tölzer Knabenchor". */
  ensembles: { id: string; name: string }[];
  /** Nur auf der Bearbeiten-Seite gesetzt — der Avatar-Crop-Button
   * braucht eine bereits existierende Person (siehe AvatarCropButton). */
  personId?: string;
}) {
  const [slug, setSlug] = useState(initial?.slug ?? "");
  const [slugTouched, setSlugTouched] = useState(Boolean(initial));
  const [firstName, setFirstName] = useState(initial?.first_name ?? "");
  const [middleName, setMiddleName] = useState(initial?.middle_name ?? "");
  const [lastName, setLastName] = useState(initial?.last_name ?? "");

  // Slug wird weiterhin automatisch aus dem (vollen) Namen abgeleitet,
  // solange die Redakteurin ihn nicht manuell angefasst hat — jetzt aus
  // den drei Namensfeldern statt aus einem einzelnen full_name-Input.
  function updateSlugFrom(first: string, middle: string, last: string) {
    if (slugTouched) return;
    setSlug(slugify([first, middle, last].filter(Boolean).join(" ")));
  }

  return (
    <form action={action} className="flex max-w-xl flex-col gap-4">
      <div className="grid grid-cols-3 gap-4">
        <Field label="Vorname" required>
          <TextInput
            name="first_name"
            required
            value={firstName}
            onChange={(e) => {
              setFirstName(e.target.value);
              updateSlugFrom(e.target.value, middleName, lastName);
            }}
          />
        </Field>
        <Field label="Zweiter Vorname">
          <TextInput
            name="middle_name"
            value={middleName}
            onChange={(e) => {
              setMiddleName(e.target.value);
              updateSlugFrom(firstName, e.target.value, lastName);
            }}
          />
        </Field>
        <Field label="Nachname" required>
          <TextInput
            name="last_name"
            required
            value={lastName}
            onChange={(e) => {
              setLastName(e.target.value);
              updateSlugFrom(firstName, middleName, e.target.value);
            }}
          />
        </Field>
      </div>

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

      <Field label="Rollen">
        <div className="flex flex-wrap gap-x-4 gap-y-2 border border-neutral-300 px-3 py-2.5">
          {ROLE_OPTIONS.map((r) => (
            <label key={r.value} className="flex items-center gap-1.5 text-sm text-neutral-700">
              <input
                type="checkbox"
                name="roles"
                value={r.value}
                defaultChecked={initial?.roles.includes(r.value)}
              />
              {r.label}
            </label>
          ))}
        </div>
      </Field>

      <Field label="Instrument (bei Solist:innen)">
        <TextInput name="instrument" defaultValue={initial?.instrument ?? ""} placeholder="z. B. Violine" />
      </Field>

      <Field label="Gehört zu Ensemble">
        <Select name="member_of_ensemble_id" defaultValue={initial?.member_of_ensemble_id ?? ""}>
          <option value="">— kein Ensemble —</option>
          {ensembles.map((e) => (
            <option key={e.id} value={e.id}>
              {e.name}
            </option>
          ))}
        </Select>
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Geburtsdatum">
          <TextInput name="birth_date" type="date" defaultValue={initial?.birth_date ?? ""} />
        </Field>
        <Field label="Sterbedatum">
          <TextInput name="death_date" type="date" defaultValue={initial?.death_date ?? ""} />
          <label className="mt-1.5 flex items-center gap-2 text-xs text-neutral-600">
            <input type="checkbox" name="is_deceased" defaultChecked={initial?.is_deceased ?? Boolean(initial?.death_date)} />
            Verstorben (auch ohne bekanntes genaues Datum)
          </label>
        </Field>
      </div>

      <Field label="Nationalität">
        <TextInput name="nationality" defaultValue={initial?.nationality ?? ""} />
      </Field>

      <Field label="Biografie">
        <TextArea name="biography_de" rows={4} defaultValue={initial?.biography_de ?? ""} />
      </Field>

      <ImageUploadField name="photo_url" initialUrl={initial?.photo_url} entityType="persons" shape="circle" label="Profilfoto" />

      {personId && initial?.photo_url && (
        <AvatarCropButton
          entityType="persons"
          entityId={personId}
          photoUrl={initial.photo_url}
          initialCrop={
            initial.avatar_crop_x != null &&
            initial.avatar_crop_y != null &&
            initial.avatar_crop_width != null &&
            initial.avatar_crop_height != null
              ? ({
                  x: initial.avatar_crop_x,
                  y: initial.avatar_crop_y,
                  width: initial.avatar_crop_width,
                  height: initial.avatar_crop_height,
                } satisfies CropRect)
              : null
          }
          path={`/persons/${personId}`}
        />
      )}

      <Field label="Website">
        <TextInput name="website_url" type="url" defaultValue={initial?.website_url ?? ""} />
      </Field>

      <label className="flex items-center gap-2 text-sm text-neutral-700">
        <input type="checkbox" name="is_verified" defaultChecked={initial?.is_verified} />
        Redaktionell geprüft
      </label>

      <div className="mt-2">
        <SubmitButton>{initial ? "Speichern" : "Person anlegen"}</SubmitButton>
      </div>
    </form>
  );
}
