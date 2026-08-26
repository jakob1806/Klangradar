// Backfill für Werke ohne Komponisten — Nutzeranfrage: "kommt häufig vor,
// dass kein Komponist da steht... bitte einbauen, dass falls kein Komponist
// gefunden werden kann, das Stück recherchiert wird und dann der Komponist
// ergänzt wird, auch wenn der seltene Einzelfall auftritt, dass der
// Komponist noch nicht in der Kartei angelegt ist". Root Cause: works.
// composer_id bleibt leer, wenn die Quelle (Titel/Beschreibung/
// Veranstaltungsseite), aus der enrich-event-references ein Werk erkannt
// hat, den Komponisten nicht nannte — enrich-work-profile deckt diesen Fall
// nicht ab (verarbeitet nur Werke, die composer_id BEREITS haben, siehe
// dortiger Kommentar). Diese Funktion schließt genau diese Lücke.
//
// Sucht den wahrscheinlichsten Wikipedia-Artikel zum reinen Werktitel
// (ohne Komponisten-Kontext, da der ja gerade unbekannt ist), lässt die KI
// konservativ den Komponistennamen aus dem Artikel extrahieren (nur wenn
// der Artikel eindeutig zu diesem Werk passt), und verknüpft/legt die
// Person an — gleiches Find-or-create-Muster wie getOrCreatePerson in
// enrich-event-references (exakter Namensabgleich, dann Fuzzy-Match via
// find_matching_person, sonst neu anlegen). Anders als dort landet ein
// unbekannter Name hier NICHT als entity_candidate zur Freigabe, sondern
// wird direkt angelegt (is_verified: false) — auf ausdrücklichen
// Nutzerwunsch, weil ein Wikipedia-Artikel, der das konkrete Werk bespricht
// und darin einen Komponisten nennt, bereits eine belastbare Quelle ist
// (anders als eine bloße Namenserwähnung in einem Veranstaltungstext).
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 10)
// Werke ohne composer_id mit noch offenem composer_checked_at.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchWikipediaExtract } from "../_shared/wikipediaExtract.ts";
import { logSystemAction } from "../_shared/systemLog.ts";
import { recordFieldSource } from "../_shared/provenance.ts";

const DEFAULT_LIMIT = 10;

const COMPOSER_EXTRACTION_FUNCTION: AiFunctionDeclaration = {
  name: "extract_work_composer",
  description: "Aus einem Wikipedia-Artikel erkannter Komponist eines Musikwerks.",
  parameters: {
    type: "object",
    properties: {
      matchesWork: {
        type: "boolean",
        description:
          "true NUR, wenn der Artikel wirklich von dem genannten Werktitel handelt (nicht von einem " +
          "gleichnamigen anderen Werk, einer Verfilmung, einem Album etc.).",
      },
      composerFullName: {
        type: "string",
        description:
          "Vollständiger Name des Komponisten, NUR wenn im Artikel eindeutig als Komponist dieses Werks " +
          "genannt (z. B. 'Johann Sebastian Bach'), sonst weglassen.",
      },
    },
    required: ["matchesWork"],
  },
};

interface WorkRow {
  id: string;
  title: string;
}

/** Dupliziert aus enrich-event-references (generateUniqueSlug) — kein
 * gemeinsamer Modul-Raum zwischen Edge Functions, siehe dortigen Kommentar. */
async function generateUniqueSlug(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  name: string,
): Promise<string> {
  const umlauts: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss", Ä: "ae", Ö: "oe", Ü: "ue" };
  let s = name;
  for (const [from, to] of Object.entries(umlauts)) s = s.split(from).join(to);
  const base = s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "") || "eintrag";

  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from("persons").select("id").eq("slug", candidate).maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
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
    .select("id, title")
    .is("composer_id", null)
    .is("composer_checked_at", null)
    .limit(limit)
    .returns<WorkRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!works || works.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine Werke ohne Komponisten übrig." }));
  }

  let composersLinked = 0;
  let personsCreated = 0;
  const errors: string[] = [];

  const FUZZY_AUTO_THRESHOLD = 0.85;

  for (const work of works) {
    try {
      const extract = await fetchWikipediaExtract(work.title);
      if (!extract) {
        // composer_checked_at trotzdem setzen — sonst würde ein Werk ohne
        // auffindbaren Artikel bei jedem Lauf erneut ausgewählt (gleiches
        // Prinzip wie profile_checked_at bei enrich-work-profile).
        await supabase.from("works").update({ composer_checked_at: new Date().toISOString() }).eq("id", work.id);
        continue;
      }

      const response = await callAiFunction(
        "Du prüfst, ob ein Wikipedia-Artikel wirklich von einem bestimmten klassischen Musikwerk handelt, und " +
          "extrahierst — nur wenn ja — dessen Komponisten. Sei konservativ: bei jedem Zweifel matchesWork=false " +
          "und keinen Komponisten liefern. Erfinde NIEMALS einen Komponisten, der nicht wortwörtlich im Text " +
          "als Komponist DIESES Werks genannt wird.",
        `Werktitel: ${work.title}\n\nWikipedia-Artikel ("${extract.articleTitle}"):\n${extract.text}`,
        COMPOSER_EXTRACTION_FUNCTION,
      );
      const args = response?.args;
      if (!args) {
        errors.push(`"${work.title}": AI-Aufruf fehlgeschlagen (alle Provider)`);
        continue; // kein Mark — bei transientem Providerfehler soll ein späterer Lauf es erneut versuchen
      }

      const name = args.matchesWork === true && typeof args.composerFullName === "string"
        ? args.composerFullName.trim()
        : "";
      if (!name) {
        await supabase.from("works").update({ composer_checked_at: new Date().toISOString() }).eq("id", work.id);
        continue;
      }

      // Find-or-create, gleiche Reihenfolge wie getOrCreatePerson in
      // enrich-event-references: exakter Namensabgleich, dann Fuzzy-Match.
      let composerId: string | null = null;
      const { data: existing } = await supabase
        .from("persons")
        .select("id")
        .ilike("full_name", name)
        .maybeSingle();
      if (existing) {
        composerId = existing.id;
      } else {
        const { data: fuzzyMatches } = await supabase.rpc("find_matching_person", { p_name: name });
        const bestMatch = fuzzyMatches?.[0] as { id: string; full_name: string; similarity: number } | undefined;
        if (bestMatch && bestMatch.similarity >= FUZZY_AUTO_THRESHOLD) {
          composerId = bestMatch.id;
          await supabase.from("entity_aliases").upsert(
            { entity_type: "person", entity_id: bestMatch.id, alias: name },
            { onConflict: "entity_type,entity_id,alias_normalized" },
          );
          await logSystemAction(supabase, "person", bestMatch.id, "fuzzy_auto_link", {
            matched_name: name,
            linked_to: bestMatch.full_name,
            similarity: bestMatch.similarity,
            work_id: work.id,
            source: "enrich-work-composer",
          });
        } else {
          const slug = await generateUniqueSlug(supabase, name);
          const { data: created, error: createError } = await supabase
            .from("persons")
            .insert({ full_name: name, slug, is_verified: false, roles: ["komponist"] })
            .select("id")
            .single();
          if (createError || !created) {
            errors.push(`"${work.title}": Komponist "${name}" anlegen fehlgeschlagen — ${createError?.message ?? "kein Ergebnis"}`);
            await supabase.from("works").update({ composer_checked_at: new Date().toISOString() }).eq("id", work.id);
            continue;
          }
          composerId = created.id;
          personsCreated++;
          await logSystemAction(supabase, "person", composerId, "ai_auto_created", {
            name,
            work_id: work.id,
            work_title: work.title,
            source: "enrich-work-composer",
            wikipedia_article: extract.articleTitle,
          }, "system (AI-Entscheidung)");
        }
      }

      const { error: updateError } = await supabase
        .from("works")
        .update({ composer_id: composerId, composer_checked_at: new Date().toISOString() })
        .eq("id", work.id);
      if (updateError) {
        errors.push(`"${work.title}": Update fehlgeschlagen — ${updateError.message}`);
        continue;
      }
      composersLinked++;
      await recordFieldSource(supabase, {
        entityType: "work",
        entityId: work.id,
        fieldName: "composer_id",
        sourceUrl: extract.pageUrl,
        sourceName: `Wikipedia (via enrich-work-composer): ${extract.articleTitle}`,
        confidence: "likely",
      });
    } catch (err) {
      errors.push(`"${work.title}": ${err instanceof Error ? err.message : String(err)}`);
      await supabase.from("works").update({ composer_checked_at: new Date().toISOString() }).eq("id", work.id);
    }
  }

  return new Response(
    JSON.stringify({
      processed: works.length,
      composersLinked,
      personsCreated,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
