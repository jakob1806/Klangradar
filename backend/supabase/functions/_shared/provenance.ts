// Schreibt/aktualisiert einen Provenienz-Eintrag für ein einzelnes
// Datenfeld einer Entität — Fundament für die Nutzeranforderung "Quellen,
// Abrufdatum und Vertrauensbewertung pro Datenfeld speichern"
// (20260907000001_field_provenance_and_aliases.sql). JEDE künftige
// Anreicherungsfunktion, die ein Datenfeld auf events/venues/persons/
// ensembles/works/festivals/organizers befüllt, soll direkt danach diese
// Funktion aufrufen, statt die Provenienz stillschweigend wegzulassen.

export type EntityType = "event" | "venue" | "person" | "ensemble" | "work" | "festival" | "organizer";
export type Confidence = "confirmed" | "likely" | "uncertain" | "unknown";

export interface FieldSource {
  entityType: EntityType;
  entityId: string;
  fieldName: string;
  sourceUrl?: string | null;
  sourceName?: string | null;
  confidence: Confidence;
}

/** Best-effort: ein Fehlschlag hier darf nie den eigentlichen
 * Anreicherungsschritt scheitern lassen (die Kerndaten sind bereits
 * geschrieben, wenn diese Funktion aufgerufen wird) — daher wird nur
 * geloggt, nie geworfen, analog zu _shared/systemLog.ts. */
export async function recordFieldSource(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  source: FieldSource,
): Promise<void> {
  const { error } = await supabase.from("field_provenance").upsert(
    {
      entity_type: source.entityType,
      entity_id: source.entityId,
      field_name: source.fieldName,
      source_url: source.sourceUrl ?? null,
      source_name: source.sourceName ?? null,
      confidence: source.confidence,
      retrieved_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "entity_type,entity_id,field_name" },
  );
  if (error) {
    console.error(
      `recordFieldSource ${source.entityType}/${source.entityId}/${source.fieldName}: ${error.message}`,
    );
  }
}

/** Mehrere Feld-Quellen in einem Rutsch, z. B. wenn eine einzelne
 * Recherche-Anfrage gleich mehrere Felder derselben Entität befüllt hat
 * (Programm, Besetzung, Beschreibung, Ticketinfo aus derselben Seite). */
export async function recordFieldSources(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  sources: FieldSource[],
): Promise<void> {
  await Promise.all(sources.map((s) => recordFieldSource(supabase, s)));
}
