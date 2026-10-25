import { Field, Select, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";

export interface WorkFormValues {
  title: string; composer_id: string | null; catalog_number: string | null; key_signature: string | null;
  composition_year: number | null; duration_minutes: number | null; genre: string | null;
  instrumentation: string | null; description_de: string | null;
  introduction_de?: string | null; introduction_source?: string | null; introduction_source_url?: string | null;
  movements?: string[] | null; movements_source?: string | null;
}

const SOURCE_LABEL: Record<string, string> = {
  wikipedia: "automatisch aus Wikipedia", programmheft: "Auszug aus einem Programmheft",
  veranstalter: "aus der Veranstalter-Beschreibung", redaktion: "von der Redaktion",
};

export function WorkForm({ action, initial, persons }: { action: (data: FormData) => void; initial?: WorkFormValues; persons: { id: string; full_name: string }[] }) {
  return (
    <form action={action} className="grid max-w-3xl gap-5 sm:grid-cols-2">
      <div className="sm:col-span-2"><Field label="Werktitel" required><TextInput name="title" required defaultValue={initial?.title ?? ""} /></Field></div>
      <Field label="Komponist:in"><Select name="composer_id" defaultValue={initial?.composer_id ?? ""}><option value="">— noch nicht zugeordnet —</option>{persons.map((person) => <option key={person.id} value={person.id}>{person.full_name}</option>)}</Select></Field>
      <Field label="Werkverzeichnis"><TextInput name="catalog_number" defaultValue={initial?.catalog_number ?? ""} placeholder="z. B. op. 67 oder BWV 244" /></Field>
      <Field label="Tonart"><TextInput name="key_signature" defaultValue={initial?.key_signature ?? ""} /></Field>
      <Field label="Genre / Form"><TextInput name="genre" defaultValue={initial?.genre ?? ""} placeholder="Sinfonie, Konzert, Oper …" /></Field>
      <Field label="Entstehungsjahr"><TextInput name="composition_year" type="number" defaultValue={initial?.composition_year ?? ""} /></Field>
      <Field label="Dauer in Minuten"><TextInput name="duration_minutes" type="number" min="1" defaultValue={initial?.duration_minutes ?? ""} /></Field>
      <div className="sm:col-span-2"><Field label="Besetzung"><TextInput name="instrumentation" defaultValue={initial?.instrumentation ?? ""} placeholder="z. B. Orchester mit Solovioline" /></Field></div>
      <div className="sm:col-span-2"><Field label="Werkbeschreibung (intern)"><TextArea name="description_de" rows={4} defaultValue={initial?.description_de ?? ""} /></Field></div>
      <div className="sm:col-span-2">
        <Field label="Werkeinführung in der App">
          <TextArea name="introduction_de" rows={9} defaultValue={initial?.introduction_de ?? ""} placeholder="Entstehung, Charakter, Besonderheiten – 2–4 Absätze für Konzertbesucher:innen" />
        </Field>
        <p className="mt-1.5 text-xs text-neutral-500">
          {initial?.introduction_source ? <>Quelle: {SOURCE_LABEL[initial.introduction_source] ?? initial.introduction_source}{initial.introduction_source_url && <> · <a href={initial.introduction_source_url} target="_blank" rel="noreferrer" className="underline">Link</a></>}. </> : null}
          Wenn du den Text änderst, gilt er als Redaktionstext und wird von der automatischen Recherche nicht mehr überschrieben.
        </p>
      </div>
      <div className="sm:col-span-2">
        <Field label="Satzfolge (ein Satz pro Zeile)">
          <TextArea name="movements" rows={6} defaultValue={(initial?.movements ?? []).join("\n")} placeholder={"I. Allegro ma non troppo\nII. Molto vivace\nIII. Adagio molto e cantabile\nIV. Finale"} />
        </Field>
        <p className="mt-1.5 text-xs text-neutral-500">{initial?.movements_source ? <>Quelle: {SOURCE_LABEL[initial.movements_source] ?? initial.movements_source}. </> : null}Leer lassen bei einsätzigen Werken.</p>
      </div>
      <div className="sm:col-span-2"><SubmitButton>{initial ? "Werk speichern" : "Werk anlegen"}</SubmitButton></div>
    </form>
  );
}
