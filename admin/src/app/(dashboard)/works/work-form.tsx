import { Field, Select, TextArea, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";

export interface WorkFormValues {
  title: string; composer_id: string | null; catalog_number: string | null; key_signature: string | null;
  composition_year: number | null; duration_minutes: number | null; genre: string | null;
  instrumentation: string | null; description_de: string | null;
}

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
      <div className="sm:col-span-2"><Field label="Werkbeschreibung"><TextArea name="description_de" rows={6} defaultValue={initial?.description_de ?? ""} /></Field></div>
      <div className="sm:col-span-2"><SubmitButton>{initial ? "Werk speichern" : "Werk anlegen"}</SubmitButton></div>
    </form>
  );
}
