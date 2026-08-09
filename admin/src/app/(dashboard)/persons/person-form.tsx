"use client";

import { useState } from "react";
import { Field, TextArea, TextInput } from "@/components/form-fields";
import { ImageUploadField } from "@/components/image-upload-field";
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
  full_name: string;
  roles: string[];
  instrument: string | null;
  nationality: string | null;
  birth_date: string | null;
  death_date: string | null;
  biography_de: string | null;
  website_url: string | null;
  photo_url: string | null;
  is_verified: boolean;
}

export function PersonForm({
  action,
  initial,
}: {
  action: (formData: FormData) => void;
  initial?: PersonFormValues;
}) {
  const [slug, setSlug] = useState(initial?.slug ?? "");
  const [slugTouched, setSlugTouched] = useState(Boolean(initial));

  return (
    <form action={action} className="flex max-w-xl flex-col gap-4">
      <Field label="Name" required>
        <TextInput
          name="full_name"
          required
          defaultValue={initial?.full_name}
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

      <div className="grid grid-cols-2 gap-4">
        <Field label="Geburtsdatum">
          <TextInput name="birth_date" type="date" defaultValue={initial?.birth_date ?? ""} />
        </Field>
        <Field label="Sterbedatum">
          <TextInput name="death_date" type="date" defaultValue={initial?.death_date ?? ""} />
        </Field>
      </div>

      <Field label="Nationalität">
        <TextInput name="nationality" defaultValue={initial?.nationality ?? ""} />
      </Field>

      <Field label="Biografie">
        <TextArea name="biography_de" rows={4} defaultValue={initial?.biography_de ?? ""} />
      </Field>

      <ImageUploadField name="photo_url" initialUrl={initial?.photo_url} entityType="persons" shape="circle" label="Profilfoto" />

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
