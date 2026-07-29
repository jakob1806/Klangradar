"use client";

import { Field, Select, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";

const TYPE_OPTIONS = [
  { value: "manual", label: "Manuell" },
  { value: "schema_org", label: "Schema.org (JSON-LD)" },
  { value: "ical", label: "iCal-Feed" },
  { value: "rss", label: "RSS-Feed" },
  { value: "api", label: "API" },
  { value: "scrape", label: "Scraping" },
];

const STATUS_OPTIONS = [
  { value: "active", label: "Aktiv" },
  { value: "paused", label: "Pausiert" },
  { value: "under_review", label: "Zu prüfen" },
  { value: "error", label: "Fehler" },
];

export interface SourceFormValues {
  name: string;
  type: string;
  url: string;
  venue_id: string | null;
  organizer_id: string | null;
  person_id: string | null;
  ensemble_id: string | null;
  crawl_frequency_minutes: number;
  legal_basis: string | null;
  status: string;
  config: Record<string, unknown> | null;
}

const CONFIG_PLACEHOLDER = `Nur für Typ "Scraping"/"API" nötig, sonst leer lassen. Beispiele:

Scraping: {"itemSelector": ".event-item", "titleSelector": ".title", "dateSelector": "time", "dateAttribute": "datetime"}
API: {"authHeaderEnvVar": "MEIN_API_TOKEN_SECRET_NAME"}

Siehe ScrapeConfig in backend/supabase/functions/ingest-source/parsers/scrape.ts für alle verfügbaren Felder.`;

export function SourceForm({
  action,
  initial,
  venues,
  organizers,
  persons,
  ensembles,
}: {
  action: (formData: FormData) => void;
  initial?: SourceFormValues;
  venues: { id: string; name: string }[];
  organizers: { id: string; name: string }[];
  persons: { id: string; full_name: string }[];
  ensembles: { id: string; name: string }[];
}) {
  return (
    <form action={action} className="flex max-w-xl flex-col gap-4">
      <Field label="Name" required>
        <TextInput name="name" required defaultValue={initial?.name} placeholder="z. B. Bayerische Staatsoper Spielplan" />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Typ" required>
          <Select name="type" required defaultValue={initial?.type ?? "manual"}>
            {TYPE_OPTIONS.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Status" required>
          <Select name="status" required defaultValue={initial?.status ?? "active"}>
            {STATUS_OPTIONS.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </Select>
        </Field>
      </div>

      <Field label="URL" required>
        <TextInput name="url" type="url" required defaultValue={initial?.url} />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field
          label="Zugehörige Venue"
          hint='Wenn diese Quelle IMMER am selben Ort stattfindet (z. B. eine einzelne Konzertreihe), hier die Venue fest hinterlegen. Liefert die Quelle pro Termin keinen eigenen Ortsnamen und ist hier nichts gesetzt, schlägt der Import für jeden Termin fehl ("no venue_id on source and RawEvent has no venueName to match against").'
        >
          <Select name="venue_id" defaultValue={initial?.venue_id ?? ""}>
            <option value="">—</option>
            {venues.map((v) => (
              <option key={v.id} value={v.id}>
                {v.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Zugehöriger Veranstalter">
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

      <div className="grid grid-cols-2 gap-4">
        <Field label="Zugehörige Person">
          <Select name="person_id" defaultValue={initial?.person_id ?? ""}>
            <option value="">—</option>
            {persons.map((p) => (
              <option key={p.id} value={p.id}>
                {p.full_name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Zugehöriges Ensemble">
          <Select name="ensemble_id" defaultValue={initial?.ensemble_id ?? ""}>
            <option value="">—</option>
            {ensembles.map((e) => (
              <option key={e.id} value={e.id}>
                {e.name}
              </option>
            ))}
          </Select>
        </Field>
      </div>

      <Field label="Crawl-Intervall (Minuten)" required>
        <TextInput name="crawl_frequency_minutes" type="number" required defaultValue={initial?.crawl_frequency_minutes ?? 1440} />
      </Field>

      <Field label="Rechtsgrundlage">
        <TextArea
          name="legal_basis"
          rows={2}
          defaultValue={initial?.legal_basis ?? ""}
          placeholder="z. B. robots.txt geprüft am ..., API-Nutzungsbedingungen unter ..."
        />
      </Field>

      <Field label="Konfiguration (JSON)">
        <TextArea
          name="config_json"
          rows={5}
          className="font-mono text-xs"
          defaultValue={initial?.config ? JSON.stringify(initial.config, null, 2) : ""}
          placeholder={CONFIG_PLACEHOLDER}
        />
      </Field>

      <div className="mt-2">
        <SubmitButton>{initial ? "Speichern" : "Quelle anlegen"}</SubmitButton>
      </div>
    </form>
  );
}
