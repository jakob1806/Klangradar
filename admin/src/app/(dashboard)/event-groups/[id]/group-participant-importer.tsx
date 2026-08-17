"use client";

import { useActionState } from "react";
import { SubmitButton } from "@/components/submit-button";
import { TextArea, TextInput } from "@/components/form-fields";
import { EventChecklist, type ChecklistEvent } from "./event-checklist";
import {
  importParsedParticipantsToGroup,
  parseParticipantTextForGroup,
  type GroupParticipantParseState,
} from "./actions";

const initialParseState: GroupParticipantParseState = { status: "idle", participants: [] };

export function GroupParticipantImporter({
  groupId,
  events,
  checkedIds,
}: {
  groupId: string;
  events: ChecklistEvent[];
  checkedIds: Set<string>;
}) {
  const [state, parseAction] = useActionState(
    parseParticipantTextForGroup.bind(null, groupId),
    initialParseState,
  );

  return (
    <div className="rounded-lg border border-blue-200 bg-blue-50/50 p-4">
      <div>
        <p className="text-sm font-semibold text-neutral-900">Besetzung mit KI einlesen</p>
        <p className="mt-1 text-xs leading-5 text-neutral-600">
          Fließtext oder Stichpunkte einfügen. Namen, Entitätstyp und konkrete Rollen werden erkannt;
          vor dem Import bleibt alles prüfbar. Gilt für die unten ausgewählten Termine der Gruppe.
        </p>
      </div>

      <form action={parseAction} className="mt-3 flex flex-col gap-3">
        <TextArea
          name="participant_text"
          rows={7}
          required
          placeholder={"Sir Simon Rattle – Dirigent\nBRSO – Orchester\nAnna Prohaska – Lady Macbeth"}
        />
        <SubmitButton pendingLabel="KI liest Besetzung…">Text auswerten</SubmitButton>
      </form>

      {state.status === "error" && (
        <p aria-live="polite" className="mt-3 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {state.error}
        </p>
      )}

      {state.status === "success" && (
        <form action={importParsedParticipantsToGroup.bind(null, groupId)} className="mt-5">
          <div className="flex items-center justify-between gap-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-neutral-600">
              {state.participants.length} erkannt
            </p>
            {state.provider && <span className="text-[11px] text-neutral-400">KI: {state.provider}</span>}
          </div>
          <input type="hidden" name="participant_count" value={state.participants.length} />

          <ul className="mt-2 flex flex-col gap-2">
            {state.participants.map((participant, index) => (
              <li key={`${participant.entityType}-${participant.name}-${index}`} className="border border-neutral-200 bg-white p-3">
                <div className="flex items-start gap-3">
                  <input
                    type="checkbox"
                    name={`selected_${index}`}
                    defaultChecked
                    className="mt-1 h-4 w-4 accent-[#0071e3]"
                    aria-label={`${participant.name} übernehmen`}
                  />
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                      <span className="font-medium text-neutral-900">{participant.name}</span>
                      <span className="text-[10px] font-semibold uppercase tracking-wide text-neutral-500">
                        {participant.entityType === "person" ? "Person" : "Ensemble"}
                      </span>
                      <span className={participant.matchedId ? "text-xs text-emerald-700" : "text-xs text-amber-700"}>
                        {participant.matchedId ? `vorhanden: ${participant.matchedName}` : "wird neu angelegt"}
                      </span>
                    </div>
                    <TextInput
                      name={`role_label_${index}`}
                      defaultValue={participant.roleLabel ?? ""}
                      placeholder="Konkrete Rolle (optional)"
                      maxLength={160}
                      className="mt-2 w-full"
                      list="group-participant-role-suggestions"
                    />
                  </div>
                </div>
                <input type="hidden" name={`name_${index}`} value={participant.name} />
                <input type="hidden" name={`entity_type_${index}`} value={participant.entityType} />
                <input type="hidden" name={`role_kind_${index}`} value={participant.roleKind ?? ""} />
                <input type="hidden" name={`matched_id_${index}`} value={participant.matchedId ?? ""} />
              </li>
            ))}
          </ul>

          <datalist id="group-participant-role-suggestions">
            <option value="Dirigent:in" />
            <option value="Solist:in" />
            <option value="Sopran" />
            <option value="Mezzosopran" />
            <option value="Tenor" />
            <option value="Bariton" />
            <option value="Bass" />
            <option value="Violine" />
            <option value="Klavier" />
            <option value="Musikalische Leitung" />
          </datalist>

          <p className="mt-3 text-xs font-medium text-neutral-500">Bei welchen Terminen?</p>
          <EventChecklist events={events} checkedIds={checkedIds} />

          <div className="mt-3">
            <SubmitButton pendingLabel="Mitwirkende werden übernommen…">Auswahl übernehmen</SubmitButton>
          </div>
        </form>
      )}
    </div>
  );
}
