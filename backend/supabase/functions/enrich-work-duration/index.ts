// Erstellt von Claude Code (07.11.2026): ergänzt die übliche Aufführungsdauer
// von Werken (works.duration_minutes). Grundlage für „Jetzt läuft …“ in der
// Live-Aktivität und für geschätzte Pausen/Konzertenden.
//
// Vorrang haben Werke aus kommenden Konzerten. Quelle: Wikipedia-Artikel
// zu „{Komponist} {Werk}“ (falls vorhanden) plus das allgemeine Wissen des
// Modells über bekannte Werke; unsichere Werke bleiben leer. Jedes Werk wird
// nur einmal geprüft (duration_checked_at).
//
// Aufruf: POST { limit?: number } (Standard 10, höchstens 25)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchWikipediaExtract } from "../_shared/wikipediaExtract.ts";
import { recordFieldSources } from "../_shared/provenance.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";

const DURATION_FUNCTION: AiFunctionDeclaration = {
  name: "work_duration",
  description: "Übliche Aufführungsdauer eines klassischen Musikwerks.",
  parameters: {
    type: "object",
    properties: {
      durationMinutes: {
        type: "number",
        description:
          "Übliche Aufführungsdauer in ganzen Minuten. NUR angeben, wenn du dir sicher bist (Text nennt sie, " +
          "oder es ist ein bekanntes Repertoirewerk). Sonst weglassen.",
      },
      confidence: { type: "string", enum: ["text", "known", "estimate"], description: "Woher die Angabe stammt." },
    },
    required: [],
  },
};

interface WorkRow {
  id: string;
  title: string;
  composer: { full_name: string } | { full_name: string }[] | null;
}

function composerName(c: WorkRow["composer"]): string | null {
  if (!c) return null;
  return Array.isArray(c) ? c[0]?.full_name ?? null : c.full_name;
}

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  let limit = 10;
  try {
    const body = await req.json();
    if (typeof body?.limit === "number" && body.limit > 0) limit = Math.min(body.limit, 25);
  } catch { /* leerer Body */ }

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  // Werke aus kommenden Konzerten zuerst.
  const { data: upcoming } = await supabase
    .from("event_works")
    .select("work_id, events!inner(start_datetime)")
    .gte("events.start_datetime", new Date().toISOString())
    .limit(2000);
  const upcomingIds = [...new Set((upcoming ?? []).map((r: { work_id: string }) => r.work_id))];

  const select = "id, title, composer:persons(full_name)";
  let works: WorkRow[] = [];
  if (upcomingIds.length) {
    const { data } = await supabase.from("works").select(select)
      .in("id", upcomingIds.slice(0, 500)).is("duration_minutes", null).is("duration_checked_at", null)
      .not("composer_id", "is", null).limit(limit).returns<WorkRow[]>();
    works = data ?? [];
  }
  if (works.length < limit) {
    const { data } = await supabase.from("works").select(select)
      .is("duration_minutes", null).is("duration_checked_at", null).not("composer_id", "is", null)
      .limit(limit - works.length).returns<WorkRow[]>();
    works = works.concat((data ?? []).filter((w) => !works.some((x) => x.id === w.id)));
  }
  if (!works.length) return new Response(JSON.stringify({ processed: 0, message: "Keine Werke ohne Dauer übrig." }));

  let updated = 0;
  const errors: string[] = [];
  for (const work of works) {
    try {
      const name = composerName(work.composer);
      const now = new Date().toISOString();
      if (!name) {
        await supabase.from("works").update({ duration_checked_at: now }).eq("id", work.id);
        continue;
      }
      const extract = await fetchWikipediaExtract(`${name} ${work.title}`).catch(() => null);
      const response = await callAiFunction(
        "Du bestimmst die übliche Aufführungsdauer klassischer Musikwerke in Minuten. Nutze den Wikipedia-Text, " +
          "wenn er zum Werk passt; bei bekannten Repertoirewerken darfst du dein Wissen nutzen. Bei unbekannten " +
          "oder mehrdeutigen Werken lieber nichts angeben als raten.",
        `Komponist: ${name}\nWerk: ${work.title}` +
          (extract ? `\n\nWikipedia („${extract.articleTitle}“):\n${extract.text.slice(0, 6000)}` : ""),
        DURATION_FUNCTION,
      );
      const args = response?.args;
      if (!args) { errors.push(`"${work.title}": KI nicht erreichbar`); continue; }
      const minutes = typeof args.durationMinutes === "number" ? Math.round(args.durationMinutes) : null;
      const ok = minutes !== null && minutes >= 1 && minutes <= 300 && args.confidence !== "estimate";
      await supabase.from("works").update({ duration_checked_at: now, ...(ok ? { duration_minutes: minutes } : {}) }).eq("id", work.id);
      if (ok) {
        updated++;
        await recordFieldSources(supabase, [{
          entityType: "work" as const,
          entityId: work.id,
          fieldName: "duration_minutes",
          sourceUrl: extract?.pageUrl ?? null,
          sourceName: args.confidence === "text" && extract ? `Wikipedia: ${extract.articleTitle}` : "KI-Wissen (enrich-work-duration)",
          confidence: args.confidence === "text" ? "likely" as const : "uncertain" as const,
        }]);
      }
    } catch (err) {
      errors.push(`"${work.title}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  return new Response(JSON.stringify({ processed: works.length, updated, errors: errors.slice(0, 10) }));
});
