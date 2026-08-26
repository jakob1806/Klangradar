// Reichert Ensemble-Profile automatisiert an — Phase 4 der grundlegend
// überarbeiteten Datenanreicherung (Nutzeranfrage für Ensembles:
// "Gründungsjahr, Mitgliederzahl, künstlerisches Profil, Leitung,
// Residenzen, Repertoire, offizielle Links"). Holt den Volltext der
// eigenen offiziellen Website (_shared/pageText.ts) und extrahiert daraus
// strukturiert Kurzbeschreibung (nur falls noch leer), Leitung,
// Residenzen, Repertoire-Schwerpunkte, Gründungsjahr und Mitgliederzahl.
//
// Gleiches Grundmuster wie enrich-person-profile/enrich-venue-details: nur
// die eigene offizielle Website als Quelle, jedes Feld nur befüllen wenn
// aktuell leer, Provenienz pro Feld, konservative Extraktion, profile_
// checked_at als Auswahl-Gate von Anfang an (siehe Konvergenz-Bug bei
// enrich-venue-details).
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 5)
// Ensembles mit website_url und noch offenem profile_checked_at.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchPageText } from "../_shared/pageText.ts";
import { recordFieldSources } from "../_shared/provenance.ts";

const DEFAULT_LIMIT = 5;

const ENRICH_FUNCTION: AiFunctionDeclaration = {
  name: "extract_ensemble_profile",
  description: "Aus dem Volltext der offiziellen Website eines Ensembles/Orchesters erkannte strukturierte Profildaten.",
  parameters: {
    type: "object",
    properties: {
      descriptionDe: {
        type: "string",
        description:
          "Kurzbeschreibung/künstlerisches Profil auf Deutsch (2-4 Sätze), NUR aus tatsächlich im Text stehenden " +
          "Informationen. Weglassen, wenn der Text dafür nicht genug hergibt.",
      },
      leadershipDe: {
        type: "string",
        description:
          "Aktuelle Leitung auf Deutsch NUR, wenn im Text explizit genannt (z. B. 'Chefdirigent: NN', " +
          "'Künstlerische Leitung: NN'), sonst weglassen.",
      },
      residencyDe: {
        type: "string",
        description: "Residenzen/feste Spielstätten NUR, wenn im Text explizit genannt, sonst weglassen.",
      },
      repertoireDe: {
        type: "string",
        description: "Repertoire-Schwerpunkte NUR, wenn im Text explizit genannt, sonst weglassen.",
      },
      foundedYear: {
        type: "number",
        description: "Gründungsjahr NUR, wenn im Text wortwörtlich genannt, sonst weglassen.",
      },
      memberCount: {
        type: "number",
        description: "Mitgliederzahl NUR, wenn im Text wortwörtlich genannt, sonst weglassen.",
      },
    },
    required: [],
  },
};

interface EnsembleRow {
  id: string;
  name: string;
  website_url: string | null;
  description_de: string | null;
  leadership_de: string | null;
  residency_de: string | null;
  repertoire_de: string | null;
  founded_year: number | null;
  member_count: number | null;
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

  const { data: ensembles, error: fetchError } = await supabase
    .from("ensembles")
    .select(
      "id, name, website_url, description_de, leadership_de, residency_de, repertoire_de, founded_year, member_count",
    )
    .is("profile_checked_at", null)
    .not("website_url", "is", null)
    .limit(limit)
    .returns<EnsembleRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!ensembles || ensembles.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine Ensembles mit fehlendem Profil übrig." }));
  }

  let updated = 0;
  const errors: string[] = [];

  for (const ensemble of ensembles) {
    try {
      const pageText = await fetchPageText(ensemble.website_url!);
      if (!pageText) {
        await supabase.from("ensembles").update({ profile_checked_at: new Date().toISOString() }).eq("id", ensemble.id);
        continue;
      }

      const response = await callAiFunction(
        "Du extrahierst strukturierte Profildaten eines Münchner Ensembles/Orchesters aus dem Volltext seiner " +
          "offiziellen Website. Sei konservativ: lieber ein leeres Feld als geraten. Erfinde NIEMALS Informationen, " +
          "die nicht wortwörtlich im Text stehen.",
        `Ensemble: ${ensemble.name}\n\nVolltext der offiziellen Website:\n${pageText}`,
        ENRICH_FUNCTION,
      );
      const args = response?.args;
      if (!args) {
        errors.push(`"${ensemble.name}": AI-Aufruf fehlgeschlagen (alle Provider)`);
        continue;
      }

      const patch: Record<string, unknown> = {};
      const provenanceFields: string[] = [];

      if (!ensemble.description_de && typeof args.descriptionDe === "string" && args.descriptionDe.trim()) {
        patch.description_de = args.descriptionDe.trim();
        provenanceFields.push("description_de");
      }
      if (!ensemble.leadership_de && typeof args.leadershipDe === "string" && args.leadershipDe.trim()) {
        patch.leadership_de = args.leadershipDe.trim();
        provenanceFields.push("leadership_de");
      }
      if (!ensemble.residency_de && typeof args.residencyDe === "string" && args.residencyDe.trim()) {
        patch.residency_de = args.residencyDe.trim();
        provenanceFields.push("residency_de");
      }
      if (!ensemble.repertoire_de && typeof args.repertoireDe === "string" && args.repertoireDe.trim()) {
        patch.repertoire_de = args.repertoireDe.trim();
        provenanceFields.push("repertoire_de");
      }
      if (!ensemble.founded_year && typeof args.foundedYear === "number" && args.foundedYear > 1000) {
        patch.founded_year = Math.round(args.foundedYear);
        provenanceFields.push("founded_year");
      }
      if (!ensemble.member_count && typeof args.memberCount === "number" && args.memberCount > 0) {
        patch.member_count = Math.round(args.memberCount);
        provenanceFields.push("member_count");
      }

      const checkedPatch = { ...patch, profile_checked_at: new Date().toISOString() };
      const { error: updateError } = await supabase.from("ensembles").update(checkedPatch).eq("id", ensemble.id);
      if (updateError) {
        errors.push(`"${ensemble.name}": Update fehlgeschlagen — ${updateError.message}`);
        continue;
      }
      if (Object.keys(patch).length > 0) {
        updated++;
        await recordFieldSources(
          supabase,
          provenanceFields.map((fieldName) => ({
            entityType: "ensemble" as const,
            entityId: ensemble.id,
            fieldName,
            sourceUrl: ensemble.website_url,
            sourceName: "Offizielle Website (via enrich-ensemble-profile)",
            confidence: "likely" as const,
          })),
        );
      }
    } catch (err) {
      errors.push(`"${ensemble.name}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      processed: ensembles.length,
      updated,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
