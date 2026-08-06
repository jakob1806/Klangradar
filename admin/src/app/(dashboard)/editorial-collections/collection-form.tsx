"use client";

import { Field, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";

export interface CollectionFormValues {
  title: string;
  slug: string;
  subtitle: string | null;
  description_de: string | null;
  is_published: boolean;
  sort_order: number;
}

export function CollectionForm({
  action,
  initial,
}: {
  action: (formData: FormData) => void;
  initial?: CollectionFormValues;
}) {
  return (
    <form action={action} className="flex max-w-xl flex-col gap-4">
      <Field label="Titel" required>
        <TextInput
          name="title"
          required
          defaultValue={initial?.title}
          placeholder="z. B. Höhepunkte der Woche"
        />
      </Field>

      <Field label="Slug" required>
        <TextInput
          name="slug"
          required
          defaultValue={initial?.slug}
          placeholder="hoehepunkte-der-woche"
        />
      </Field>

      <Field label="Untertitel">
        <TextInput name="subtitle" defaultValue={initial?.subtitle ?? ""} placeholder="Kurzer Teaser für die Karte" />
      </Field>

      <Field label="Beschreibung">
        <TextArea name="description_de" rows={4} defaultValue={initial?.description_de ?? ""} />
      </Field>

      <Field label="Sortierung" hint="Niedrigere Zahl zuerst.">
        <TextInput name="sort_order" type="number" defaultValue={initial?.sort_order ?? 0} />
      </Field>

      <label className="flex items-center gap-2 text-sm text-neutral-700">
        <input type="checkbox" name="is_published" defaultChecked={initial?.is_published ?? false} />
        Veröffentlicht (in der App sichtbar)
      </label>

      <div className="mt-2">
        <SubmitButton>{initial ? "Speichern" : "Sammlung anlegen"}</SubmitButton>
      </div>
    </form>
  );
}
