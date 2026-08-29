import { Field, Select } from "@/components/form-fields";

// Wird nur gerendert, wenn der Nutzer mehrere genehmigte Organizer-Claims
// hat — bei genau einem wird organizer_id serverseitig injiziert (siehe
// events/actions.ts), ein Auswahlfeld für eine einzige Option wäre nur
// Rauschen. Zeigt AUSSCHLIESSLICH die eigenen genehmigten Institutionen,
// nie die volle organizers-Tabelle.
export function OrganizerPicker({
  organizers,
  initial,
}: {
  organizers: { id: string; name: string }[];
  initial?: string;
}) {
  return (
    <Field label="Institution" required>
      <Select name="organizer_id" required defaultValue={initial ?? ""}>
        <option value="" disabled>
          Bitte wählen…
        </option>
        {organizers.map((o) => (
          <option key={o.id} value={o.id}>
            {o.name}
          </option>
        ))}
      </Select>
    </Field>
  );
}
