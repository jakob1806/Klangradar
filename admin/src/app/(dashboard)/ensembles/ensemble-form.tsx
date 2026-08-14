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

const TYPE_OPTIONS = [
  { value: "chor", label: "Chor" },
  { value: "orchester", label: "Orchester" },
  { value: "kammerensemble", label: "Kammerensemble" },
  { value: "big_band", label: "Big Band" },
  { value: "sonstiges", label: "Sonstiges" },
];

const FAMILY_ROLE_OPTIONS = [
  ["", "— keine Familienrolle —"],
  ["institution", "Dachorganisation"],
  ["orchestra", "Orchester"],
  ["choir", "Chor"],
  ["childrens_choir", "Kinderchor"],
  ["extra_choir", "Extra-/Zusatzchor"],
  ["ballet", "Ballett"],
  ["opera_studio", "Opernstudio"],
  ["statisterie", "Statisterie"],
  ["child_statisterie", "Kinderstatisterie"],
  ["other", "Sonstige Untergruppe"],
] as const;

export interface EnsembleFormValues {
  slug: string;
  name: string;
  type: string;
  description_de: string | null;
  founded_year: number | null;
  member_count: number | null;
  home_venue_id: string | null;
  parent_ensemble_id: string | null;
  family_role: string | null;
  is_family_root: boolean;
  is_resolution_placeholder: boolean;
  website_url: string | null;
  photo_url: string | null;
  avatar_crop_x: number | null;
  avatar_crop_y: number | null;
  avatar_crop_width: number | null;
  avatar_crop_height: number | null;
  is_verified: boolean;
}

export function EnsembleForm({
  action,
  initial,
  venues,
  ensembles,
  ensembleId,
}: {
  action: (formData: FormData) => void;
  initial?: EnsembleFormValues;
  venues: { id: string; name: string }[];
  /** Für die "Gehört zu Ensemble"-Auswahl — schließt das aktuell bearbeitete
   * Ensemble selbst aus (kein Selbstverweis, siehe DB-Check-Constraint). */
  ensembles: { id: string; name: string }[];
  /** Nur auf der Bearbeiten-Seite gesetzt — siehe AvatarCropButton. */
  ensembleId?: string;
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

      <Field label="Typ" required>
        <Select name="type" required defaultValue={initial?.type ?? "chor"}>
          {TYPE_OPTIONS.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </Select>
      </Field>

      <Field label="Beschreibung">
        <TextArea name="description_de" rows={3} defaultValue={initial?.description_de ?? ""} />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Gründungsjahr">
          <TextInput name="founded_year" type="number" defaultValue={initial?.founded_year ?? ""} />
        </Field>
        <Field label="Mitgliederzahl">
          <TextInput name="member_count" type="number" defaultValue={initial?.member_count ?? ""} />
        </Field>
      </div>

      <Field label="Heimat-Venue">
        <Select name="home_venue_id" defaultValue={initial?.home_venue_id ?? ""}>
          <option value="">—</option>
          {venues.map((v) => (
            <option key={v.id} value={v.id}>
              {v.name}
            </option>
          ))}
        </Select>
      </Field>

      <fieldset className="space-y-4 border border-black/[0.08] bg-neutral-50 p-4">
        <legend className="type-label px-2 !text-neutral-700">Ensemblefamilie</legend>
        <Field label="Gehört zu Ensemble" hint="Ordnet das Ensemble einer Dachorganisation oder einem übergeordneten Klangkörper zu.">
          <Select name="parent_ensemble_id" defaultValue={initial?.parent_ensemble_id ?? ""}>
            <option value="">— kein übergeordnetes Ensemble —</option>
            {ensembles
              .filter((e) => e.id !== ensembleId)
              .map((e) => (
                <option key={e.id} value={e.id}>
                  {e.name}
                </option>
              ))}
          </Select>
        </Field>
        <Field label="Rolle innerhalb der Familie">
          <Select name="family_role" defaultValue={initial?.family_role ?? ""}>
            {FAMILY_ROLE_OPTIONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </Select>
        </Field>
        <label className="flex items-center gap-2 text-sm text-neutral-700">
          <input type="checkbox" name="is_family_root" defaultChecked={initial?.is_family_root} />
          Als Dachorganisation/Familienwurzel führen
        </label>
      </fieldset>

      <ImageUploadField name="photo_url" initialUrl={initial?.photo_url} entityType="ensembles" shape="rounded" label="Foto" />

      {ensembleId && initial?.photo_url && (
        <AvatarCropButton
          entityType="ensembles"
          entityId={ensembleId}
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
          path={`/ensembles/${ensembleId}`}
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
        <SubmitButton>{initial ? "Speichern" : "Ensemble anlegen"}</SubmitButton>
      </div>
    </form>
  );
}
