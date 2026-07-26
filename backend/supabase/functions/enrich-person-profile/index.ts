// Reichert Personen-Profile automatisiert an — Phase 4 der grundlegend
// überarbeiteten Datenanreicherung (Nutzeranfrage: "kurze und ausführliche
// Biografie", "Ausbildung, Karrierestationen, künstlerischer Schwerpunkt/
// Repertoire", "aktuelle relevante Rollen: Chefdirigent, Professur,
// Orchestermitgliedschaft"). Holt den Volltext der eigenen offiziellen
// Website (_shared/pageText.ts) und extrahiert daraus strukturiert
// Kurzbiografie (nur falls noch leer), Ausbildung/Karrierestationen,
// aktuelle Rollen, Auszeichnungen, wichtige Aufnahmen und
// Repertoire-Schwerpunkte.
//
// Gleiches Grundmuster wie enrich-venue-details: nur die eigene offizielle
// Website als Quelle, jedes Feld nur befüllen wenn aktuell leer (nie eine
// bestehende, ggf. redaktionell gepflegte Angabe überschreiben), Provenienz
// pro Feld via _shared/provenance.ts, konservative Extraktion ("nicht
// erfinden"). profile_checked_at als Auswahl-Gate von Anfang an (siehe
// Konvergenz-Bug bei enrich-venue-details) statt eines Datenfelds.
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 5,
// klein gehalten wegen des Seitenabrufs pro Person, siehe
// WORKER_RESOURCE_LIMIT-Erfahrung bei enrich-event-references) Personen mit
// website_url und noch offenem profile_checked_at.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchPageText } from "../_shared/pageText.ts";
import { recordFieldSources } from "../_shared/provenance.ts";

const DEFAULT_LIMIT = 5;

const ENRICH_FUNCTION: AiFunctionDeclaration = {
  name: "extract_person_profile",
  description: "Aus dem Volltext der offiziellen Website einer Musikerin/eines Musikers erkannte strukturierte Profildaten.",
  parameters: {
    type: "object",
    properties: {
      biographyDe: {
        type: "string",
        description:
          "Kurzbiografie auf Deutsch (2-4 Sätze), NUR aus tatsächlich im Text stehenden Informationen — keine " +
          "erfundenen Details, keine Floskeln. Weglassen, wenn der Text dafür nicht genug hergibt.",
      },
      educationCareerDe: {
        type: "string",
        description:
          "Ausbildung und wichtige Karrierestationen auf Deutsch (Stichpunkte oder Kurztext) NUR, wenn im Text " +
          "explizit genannt (z. B. Studium, frühere Positionen, Wettbewerbserfolge als Karrierestation), sonst weglassen.",
      },
      currentRolesDe: {
        type: "string",
        description:
          "Aktuelle relevante Rollen auf Deutsch NUR, wenn im Text explizit genannt (z. B. 'Chefdirigent des X', " +
          "'Professur an der Y', 'Mitglied im Z-Orchester'), sonst weglassen.",
      },
      awards: {
        type: "array",
        items: { type: "string" },
        description: "Auszeichnungen/Preise NUR, wenn im Text wortwörtlich genannt, sonst weglassen.",
      },
      notableRecordings: {
        type: "array",
        items: { type: "string" },
        description: "Wichtige Aufnahmen/Einspielungen NUR, wenn im Text wortwörtlich genannt, sonst weglassen.",
      },
      repertoireHighlights: {
        type: "array",
        items: { type: "string" },
        description: "Repertoire-Schwerpunkte NUR, wenn im Text explizit genannt, sonst weglassen.",
      },
    },
    required: [],
  },
};

interface PersonRow {
  id: string;
  full_name: string;
  website_url: string | null;
  biography_de: string | null;
  education_career_de: string | null;
  current_roles_de: string | null;
  awards: string[] | null;
  notable_recordings: string[] | null;
  repertoire_highlights: string[] | null;
}

Deno.serve(async (req) => {
  if (!hasAnyAiProviderConfigured()) {
    return new Response(
      JSON.stringify({ error: "Kein AI-Provider-Secret gesetzt (CEREBRAS_API_KEY, NVIDIA_API_KEY oder GEMINI_API_KEY)" }),
      { status: 500 },
    );
  }

  let body: { limit?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0 ? Math.min(body.limit, 20) : DEFAULT_LIMIT;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: persons, error: fetchError } = await supabase
    .from("persons")
    .select(
      "id, full_name, website_url, biography_de, education_career_de, current_roles_de, awards, notable_recordings, repertoire_highlights",
    )
    .is("profile_checked_at", null)
    .not("website_url", "is", null)
    .limit(limit)
    .returns<PersonRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!persons || persons.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine Personen mit fehlendem Profil übrig." }));
  }

  let updated = 0;
  const errors: string[] = [];

  for (const person of persons) {
    try {
      const pageText = await fetchPageText(person.website_url!);
      if (!pageText) {
        // profile_checked_at trotzdem setzen — sonst würden Personen mit
        // dauerhaft nicht abrufbarer Seite (robots.txt-Sperre, tote Seite)
        // bei jedem Lauf erneut ausgewählt und der Backfill käme nie zum
        // Ende (gleicher Bug wie live bei enrich-venue-details entdeckt).
        await supabase.from("persons").update({ profile_checked_at: new Date().toISOString() }).eq("id", person.id);
        continue;
      }

      const response = await callAiFunction(
        "Du extrahierst strukturierte Profildaten einer Musikerin/eines Musikers aus dem Volltext ihrer/seiner " +
          "offiziellen Website. Sei konservativ: lieber ein leeres Feld als geraten. Erfinde NIEMALS Informationen, " +
          "die nicht wortwörtlich im Text stehen.",
        `Person: ${person.full_name}\n\nVolltext der offiziellen Website:\n${pageText}`,
        ENRICH_FUNCTION,
      );
      const args = response?.args;
      if (!args) {
        // Kein Mark bei transientem Providerfehler — ein späterer Lauf soll
        // es erneut versuchen (gleiches Prinzip wie enrich-event-references).
        errors.push(`"${person.full_name}": AI-Aufruf fehlgeschlagen (alle Provider)`);
        continue;
      }

      const patch: Record<string, unknown> = {};
      const provenanceFields: string[] = [];

      if (!person.biography_de && typeof args.biographyDe === "string" && args.biographyDe.trim()) {
        patch.biography_de = args.biographyDe.trim();
        provenanceFields.push("biography_de");
      }
      if (!person.education_career_de && typeof args.educationCareerDe === "string" && args.educationCareerDe.trim()) {
        patch.education_career_de = args.educationCareerDe.trim();
        provenanceFields.push("education_career_de");
      }
      if (!person.current_roles_de && typeof args.currentRolesDe === "string" && args.currentRolesDe.trim()) {
        patch.current_roles_de = args.currentRolesDe.trim();
        provenanceFields.push("current_roles_de");
      }
      // awards/notable_recordings/repertoire_highlights sind jsonb-Arrays
      // von OBJEKTEN ({title, note}/{title, label, year, url}), nicht von
      // reinen Strings — so erwartet es die bestehende Flutter-Detailseite
      // (_BioSection in person_detail_screen.dart, e['title']/e['note']
      // etc.). Das AI-Schema liefert schlichte Strings, hier daher in die
      // erwartete Objektform wrappen statt roh zu übernehmen.
      if (
        (!person.awards || person.awards.length === 0) &&
        Array.isArray(args.awards) &&
        args.awards.length > 0
      ) {
        const items = args.awards.filter((a: unknown) => typeof a === "string" && a.trim());
        if (items.length > 0) {
          patch.awards = items.map((title: string) => ({ title }));
          provenanceFields.push("awards");
        }
      }
      if (
        (!person.notable_recordings || person.notable_recordings.length === 0) &&
        Array.isArray(args.notableRecordings) &&
        args.notableRecordings.length > 0
      ) {
        const items = args.notableRecordings.filter((a: unknown) => typeof a === "string" && a.trim());
        if (items.length > 0) {
          patch.notable_recordings = items.map((title: string) => ({ title }));
          provenanceFields.push("notable_recordings");
        }
      }
      if (
        (!person.repertoire_highlights || person.repertoire_highlights.length === 0) &&
        Array.isArray(args.repertoireHighlights) &&
        args.repertoireHighlights.length > 0
      ) {
        const items = args.repertoireHighlights.filter((a: unknown) => typeof a === "string" && a.trim());
        if (items.length > 0) {
          patch.repertoire_highlights = items.map((title: string) => ({ title }));
          provenanceFields.push("repertoire_highlights");
        }
      }

      const checkedPatch = { ...patch, profile_checked_at: new Date().toISOString() };
      const { error: updateError } = await supabase.from("persons").update(checkedPatch).eq("id", person.id);
      if (updateError) {
        errors.push(`"${person.full_name}": Update fehlgeschlagen — ${updateError.message}`);
        continue;
      }
      if (Object.keys(patch).length > 0) {
        updated++;
        await recordFieldSources(
          supabase,
          provenanceFields.map((fieldName) => ({
            entityType: "person" as const,
            entityId: person.id,
            fieldName,
            sourceUrl: person.website_url,
            sourceName: "Offizielle Website (via enrich-person-profile)",
            confidence: "likely" as const,
          })),
        );
      }
    } catch (err) {
      errors.push(`"${person.full_name}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      processed: persons.length,
      updated,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
