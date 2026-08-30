import { createClient } from "@/lib/supabase/server";
import {
  EDITABLE_FIELDS_FOR_ENTITY_TYPE,
  TABLE_FOR_ENTITY_TYPE,
  resolveEntityNames,
  type ClaimableEntityType,
} from "@/lib/entity-tables";
import { SuggestionList, type UiFieldChange, type UiSuggestion } from "./suggestion-list";

export const dynamic = "force-dynamic";

interface SuggestionRow {
  id: string;
  entity_type: ClaimableEntityType;
  entity_id: string;
  user_id: string;
  proposed_changes: unknown;
  created_at: string;
}

type ValidSuggestionRow = Omit<SuggestionRow, "entity_type" | "proposed_changes"> & {
  entity_type: ClaimableEntityType;
  proposed_changes: Record<string, string | null>;
};

function isClaimableEntityType(value: string): value is ClaimableEntityType {
  return value === "organizer" || value === "venue" || value === "person" || value === "ensemble";
}

function isChangeRecord(value: unknown): value is Record<string, string | null> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export default async function EntityEditSuggestionsPage() {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("entity_edit_suggestions")
    .select("id, entity_type, entity_id, user_id, proposed_changes, created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .returns<SuggestionRow[]>();

  // Ältere bzw. manuell angelegte JSON-Datensätze können außerhalb des
  // erwarteten Formats liegen. Ein einzelner solcher Vorschlag darf die
  // komplette Redaktionsseite nicht in eine Fehlerseite schicken.
  const rawSuggestions = data ?? [];
  const suggestions = rawSuggestions.filter(
    (suggestion): suggestion is ValidSuggestionRow =>
      isClaimableEntityType(suggestion.entity_type) && isChangeRecord(suggestion.proposed_changes),
  );
  const skippedSuggestionCount = rawSuggestions.length - suggestions.length;

  // Aktuelle Werte je betroffener Entität gebündelt nachladen (für den Diff
  // "alt → neu"), gruppiert nach Typ wie bei resolveEntityNames — kein
  // eingebetteter Join möglich, da entity_edit_suggestions polymorph ist.
  const idsByType = new Map<ClaimableEntityType, Set<string>>();
  for (const s of suggestions) {
    if (!idsByType.has(s.entity_type)) idsByType.set(s.entity_type, new Set());
    idsByType.get(s.entity_type)!.add(s.entity_id);
  }
  const currentValues = new Map<string, Record<string, unknown>>();
  await Promise.all(
    Array.from(idsByType.entries()).map(async ([entityType, ids]) => {
      const { data: rows } = await supabase
        .from(TABLE_FOR_ENTITY_TYPE[entityType])
        .select("*")
        .in("id", Array.from(ids));
      for (const row of (rows ?? []) as Record<string, unknown>[]) {
        currentValues.set(`${entityType}:${row.id as string}`, row);
      }
    }),
  );

  const [entityNames, requesterProfiles] = await Promise.all([
    resolveEntityNames(supabase, suggestions.map((s) => ({ entityType: s.entity_type, entityId: s.entity_id }))),
    (async () => {
      const userIds = [...new Set(suggestions.map((s) => s.user_id))];
      if (userIds.length === 0) return new Map<string, string>();
      const { data: profiles } = await supabase.from("profiles").select("id, display_name").in("id", userIds);
      return new Map((profiles ?? []).map((p) => [p.id as string, (p.display_name as string | null) ?? (p.id as string)]));
    })(),
  ]);

  const uiSuggestions: UiSuggestion[] = suggestions.map((s) => {
    const fields = EDITABLE_FIELDS_FOR_ENTITY_TYPE[s.entity_type] as Record<string, string>;
    const current = currentValues.get(`${s.entity_type}:${s.entity_id}`) ?? {};
    const changes: UiFieldChange[] = Object.entries(fields)
      .filter(([field]) => field in s.proposed_changes)
      .map(([field, label]) => ({
        field,
        label,
        oldValue: (current[field] as string | null) ?? "",
        newValue: s.proposed_changes[field] ?? "",
      }));

    return {
      id: s.id,
      entityType: s.entity_type,
      entityName: entityNames.get(`${s.entity_type}:${s.entity_id}`) ?? "(unbekannt)",
      requesterLabel: requesterProfiles.get(s.user_id) ?? s.user_id,
      createdAt: s.created_at,
      changes,
    };
  });

  return (
    <div className="p-8">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Profiländerungsvorschläge</h1>
        <p className="mt-1 max-w-xl text-sm text-neutral-500">
          Von Veranstaltern vorgeschlagene Änderungen an geclaimten Institutionen/Venues/Personen/Ensembles
          — bei Genehmigung wird der Vorschlag direkt auf die Stammdaten-Zeile angewendet.
        </p>
        <p className="mt-2 text-xs text-neutral-500">{suggestions.length} offen</p>
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Vorschläge nicht laden: {error.message}</p>}
      {skippedSuggestionCount > 0 && (
        <p className="mt-6 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          {skippedSuggestionCount} unvollständiger Vorschlag konnte nicht angezeigt werden. Die übrigen Vorschläge stehen weiterhin zur Prüfung bereit.
        </p>
      )}

      {!error && (
        <div className="mt-6">
          <SuggestionList suggestions={uiSuggestions} />
        </div>
      )}
    </div>
  );
}
