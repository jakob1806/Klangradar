"use client";

// Checkbox-Liste der Gruppentermine für Formulare (Hinzufügen, vorbelegt
// mit allen Terminen) und für die Mitgliedschafts-Bearbeitung
// (membership-editor.tsx, vorbelegt mit den aktuell verknüpften Terminen).

export interface ChecklistEvent {
  id: string;
  label: string;
}

export function EventChecklist({
  events,
  checkedIds,
  name = "event_ids",
}: {
  events: ChecklistEvent[];
  checkedIds: Set<string>;
  name?: string;
}) {
  return (
    <div className="flex flex-col gap-1 rounded-md border border-neutral-200 bg-white p-2">
      {events.map((e) => (
        <label key={e.id} className="flex items-center gap-2 text-xs text-neutral-700">
          <input
            type="checkbox"
            name={name}
            value={e.id}
            defaultChecked={checkedIds.has(e.id)}
            className="h-3.5 w-3.5 rounded border-neutral-300"
          />
          {e.label}
        </label>
      ))}
    </div>
  );
}
