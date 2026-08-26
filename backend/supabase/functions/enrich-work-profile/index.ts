// Reichert Werk-Profile automatisiert an — Phase 5 der grundlegend
// überarbeiteten Datenanreicherung (Nutzeranfrage zu Werken:
// "Instrumentierung, alternative Titel und Satzfolge, wo verlässlich
// verfügbar", zusätzlich Genre/Kompositionsjahr/Kurzbeschreibung falls noch
// leer). Werke haben anders als Venues/Künstler/Ensembles keine eigene
// offizielle Website — als Quelle dient stattdessen der wahrscheinlichste
// Wikipedia-Artikel zu "{Komponist} {Werktitel}" (_shared/wikipediaExtract.ts).
//
// Gleiches Grundmuster wie enrich-person-profile/enrich-venue-details: jedes
// Feld nur befüllen wenn aktuell leer, Provenienz pro Feld, konservative
// Extraktion ("nicht erfinden"), profile_checked_at als Auswahl-Gate von
// Anfang an (siehe Konvergenz-Bug bei enrich-venue-details).
//
// Nur Werke mit gesetztem composer_id werden verarbeitet — ohne Komponisten-
// Namen wäre die Wikipedia-Suchanfrage zu unspezifisch und würde häufig
// falsche Artikel treffen.
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 5)
// Werke mit composer_id und noch offenem profile_checked_at.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchWikipediaExtract } from "../_shared/wikipediaExtract.ts";
import { recordFieldSources } from "../_shared/provenance.ts";

const DEFAULT_LIMIT = 5;

const ENRICH_FUNCTION: AiFunctionDeclaration = {
  name: "extract_work_profile",
  description: "Aus einem Wikipedia-Artikel erkannte strukturierte Profildaten eines Musikwerks.",
  parameters: {
    type: "object",
    properties: {
      instrumentation: {
        type: "string",
        description:
          "Besetzung/Instrumentierung auf Deutsch NUR, wenn im Text explizit genannt (z. B. 'Streichorchester, " +
          "zwei Klaviere'), sonst weglassen.",
      },
      alternativeTitles: {
        type: "array",
        items: { type: "string" },
        description: "Alternative Titel/Beinamen des Werks NUR, wenn im Text wortwörtlich genannt, sonst weglassen.",
      },
      movements: {
        type: "array",
        items: { type: "string" },
        description: "Satzfolge (ein Eintrag pro Satz) NUR, wenn im Text explizit als Liste/Aufzählung genannt, sonst weglassen.",
      },
      descriptionDe: {
        type: "string",
        description:
          "Kurzbeschreibung des Werks auf Deutsch (1-3 Sätze), NUR aus tatsächlich im Text stehenden " +
          "Informationen. Weglassen, wenn der Text dafür nicht genug hergibt.",
      },
      genre: {
        type: "string",
        description: "Gattung/Genre (z. B. 'Sinfonie', 'Klavierkonzert') NUR, wenn im Text eindeutig erkennbar, sonst weglassen.",
      },
      compositionYear: {
        type: "number",
        description: "Entstehungs-/Kompositionsjahr NUR, wenn im Text wortwörtlich genannt, sonst weglassen.",
      },
    },
    required: [],
  },
};

interface WorkRow {
  id: string;
  title: string;
  composer_id: string;
  instrumentation: string | null;
  alternative_titles: string[] | null;
  movements: string[] | null;
  description_de: string | null;
  genre: string | null;
  composition_year: number | null;
  composer: { full_name: string } | { full_name: string }[] | null;
}

function composerName(composer: WorkRow["composer"]): string | null {
  if (!composer) return null;
  return Array.isArray(composer) ? composer[0]?.full_name ?? null : composer.full_name;
}

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

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

  const { data: works, error: fetchError } = await supabase
    .from("works")
    .select(
      "id, title, composer_id, instrumentation, alternative_titles, movements, description_de, genre, composition_year, composer:persons(full_name)",
    )
    .is("profile_checked_at", null)
    .not("composer_id", "is", null)
    .limit(limit)
    .returns<WorkRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!works || works.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine Werke mit fehlendem Profil übrig." }));
  }

  let updated = 0;
  const errors: string[] = [];

  for (const work of works) {
    try {
      const name = composerName(work.composer);
      if (!name) {
        await supabase.from("works").update({ profile_checked_at: new Date().toISOString() }).eq("id", work.id);
        continue;
      }

      const extract = await fetchWikipediaExtract(`${name} ${work.title}`);
      if (!extract) {
        // profile_checked_at trotzdem setzen — sonst würden Werke ohne
        // auffindbaren Wikipedia-Artikel bei jedem Lauf erneut ausgewählt
        // und der Backfill käme nie zum Ende (gleicher Bug wie live bei
        // enrich-venue-details entdeckt).
        await supabase.from("works").update({ profile_checked_at: new Date().toISOString() }).eq("id", work.id);
        continue;
      }

      const response = await callAiFunction(
        "Du extrahierst strukturierte Profildaten eines klassischen Musikwerks aus einem Wikipedia-Artikel. " +
          "Der Artikel könnte auch von einer anderen Person/einem anderen Werk mit ähnlichem Namen handeln — " +
          "prüfe, ob er wirklich zum genannten Komponisten und Werktitel passt, und liefere im Zweifel leere " +
          "Felder. Sei konservativ: lieber ein leeres Feld als geraten. Erfinde NIEMALS Informationen, die " +
          "nicht wortwörtlich im Text stehen.",
        `Komponist: ${name}\nWerktitel: ${work.title}\n\nWikipedia-Artikel ("${extract.articleTitle}"):\n${extract.text}`,
        ENRICH_FUNCTION,
      );
      const args = response?.args;
      if (!args) {
        // Kein Mark bei transientem Providerfehler — ein späterer Lauf soll
        // es erneut versuchen (gleiches Prinzip wie enrich-event-references).
        errors.push(`"${work.title}": AI-Aufruf fehlgeschlagen (alle Provider)`);
        continue;
      }

      const patch: Record<string, unknown> = {};
      const provenanceFields: string[] = [];

      if (!work.instrumentation && typeof args.instrumentation === "string" && args.instrumentation.trim()) {
        patch.instrumentation = args.instrumentation.trim();
        provenanceFields.push("instrumentation");
      }
      if (
        (!work.alternative_titles || work.alternative_titles.length === 0) &&
        Array.isArray(args.alternativeTitles) &&
        args.alternativeTitles.length > 0
      ) {
        const items = args.alternativeTitles.filter((a: unknown) => typeof a === "string" && a.trim());
        if (items.length > 0) {
          patch.alternative_titles = items;
          provenanceFields.push("alternative_titles");
        }
      }
      if (
        (!work.movements || work.movements.length === 0) &&
        Array.isArray(args.movements) &&
        args.movements.length > 0
      ) {
        const items = args.movements.filter((a: unknown) => typeof a === "string" && a.trim());
        if (items.length > 0) {
          patch.movements = items;
          provenanceFields.push("movements");
        }
      }
      if (!work.description_de && typeof args.descriptionDe === "string" && args.descriptionDe.trim()) {
        patch.description_de = args.descriptionDe.trim();
        provenanceFields.push("description_de");
      }
      if (!work.genre && typeof args.genre === "string" && args.genre.trim()) {
        patch.genre = args.genre.trim();
        provenanceFields.push("genre");
      }
      if (!work.composition_year && typeof args.compositionYear === "number" && args.compositionYear > 1000) {
        patch.composition_year = Math.round(args.compositionYear);
        provenanceFields.push("composition_year");
      }

      const checkedPatch = { ...patch, profile_checked_at: new Date().toISOString() };
      const { error: updateError } = await supabase.from("works").update(checkedPatch).eq("id", work.id);
      if (updateError) {
        errors.push(`"${work.title}": Update fehlgeschlagen — ${updateError.message}`);
        continue;
      }
      if (Object.keys(patch).length > 0) {
        updated++;
        await recordFieldSources(
          supabase,
          provenanceFields.map((fieldName) => ({
            entityType: "work" as const,
            entityId: work.id,
            fieldName,
            sourceUrl: extract.pageUrl,
            sourceName: `Wikipedia (via enrich-work-profile): ${extract.articleTitle}`,
            confidence: "likely" as const,
          })),
        );
      }
    } catch (err) {
      errors.push(`"${work.title}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      processed: works.length,
      updated,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
