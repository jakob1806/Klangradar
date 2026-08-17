"use client";

import { Field, Select, TextArea, TextInput } from "@/components/form-fields";
import { ImageUploadField } from "@/components/image-upload-field";
import { SubmitButton } from "@/components/submit-button";

export interface FestivalFormValues {
  name: string;
  slug: string;
  description_de: string | null;
  organizer_id: string | null;
  recurring: boolean;
  website_url: string | null;
  photo_url: string | null;
  start_date: string | null;
  end_date: string | null;
}

export function FestivalForm({
  action,
  initial,
  organizers,
}: {
  action: (formData: FormData) => void;
  initial?: FestivalFormValues;
  organizers: { id: string; name: string }[];
}) {
  return (
    <form action={action} className="flex max-w-xl flex-col gap-4">
      <Field label="Name" required>
        <TextInput name="name" required defaultValue={initial?.name} placeholder="z. B. Münchner Opernfestspiele" />
      </Field>

      <Field label="Slug" required>
        <TextInput name="slug" required defaultValue={initial?.slug} placeholder="muenchner-opernfestspiele" />
      </Field>

      <Field label="Beschreibung">
        <TextArea name="description_de" rows={4} defaultValue={initial?.description_de ?? ""} />
      </Field>

      <Field label="Veranstalter">
        <Select name="organizer_id" defaultValue={initial?.organizer_id ?? ""}>
          <option value="">— keiner —</option>
          {organizers.map((o) => (
            <option key={o.id} value={o.id}>
              {o.name}
            </option>
          ))}
        </Select>
      </Field>

      <Field label="Website">
        <TextInput name="website_url" type="url" defaultValue={initial?.website_url ?? ""} placeholder="https://…" />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Beginn" hint="Aktiviert automatisch das Saisonal/Festival-Modul im Home-Feed, siehe docs/08">
          <TextInput name="start_date" type="date" defaultValue={initial?.start_date ?? ""} />
        </Field>
        <Field label="Ende">
          <TextInput name="end_date" type="date" defaultValue={initial?.end_date ?? ""} />
        </Field>
      </div>

      <label className="flex items-center gap-2 text-sm text-neutral-700">
        <input type="checkbox" name="recurring" defaultChecked={initial?.recurring ?? false} />
        Jährlich wiederkehrend
      </label>

      <ImageUploadField name="photo_url" initialUrl={initial?.photo_url} entityType="festivals" shape="rounded" label="Foto" />

      <div className="mt-2">
        <SubmitButton>{initial ? "Speichern" : "Festival anlegen"}</SubmitButton>
      </div>
    </form>
  );
}
