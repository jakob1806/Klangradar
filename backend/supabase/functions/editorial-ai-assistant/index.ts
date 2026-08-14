import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createGeminiProvider } from "../_shared/ai/providers/gemini.ts";
import type { AiFunctionDeclaration } from "../_shared/ai/types.ts";
import { researchViaGeminiGrounding } from "../_shared/geminiGroundedSearch.ts";
import { fetchPageText } from "../_shared/pageText.ts";
import { searchTavily } from "../_shared/tavily.ts";
import { searchDuckDuckGo } from "../_shared/duckDuckGoSearch.ts";
import { fetchWikipediaExtract } from "../_shared/wikipediaExtract.ts";

type EntityType = "event" | "person" | "ensemble" | "work" | "venue";
type Proposal = { field: string; value: unknown; confidence: "confirmed" | "likely" | "unclear"; rationale?: string; sourceUrls?: string[] };

const CONFIG: Record<EntityType, { table: string; name: string; fields: string[] }> = {
  person: { table: "persons", name: "full_name", fields: ["full_name", "birth_date", "death_date", "nationality", "instrument", "roles", "biography_de", "education_career_de", "current_roles_de", "website_url"] },
  ensemble: { table: "ensembles", name: "name", fields: ["name", "type", "description_de", "founded_year", "member_count", "leadership_de", "residency_de", "repertoire_de", "website_url"] },
  work: { table: "works", name: "title", fields: ["title", "composer_id", "catalog_number", "key_signature", "composition_year", "duration_minutes", "genre", "description_de", "movements", "instrumentation", "alternative_titles"] },
  event: { table: "events", name: "title", fields: ["title", "subtitle", "description_de", "program_notes_de", "duration_minutes", "start_datetime", "end_datetime", "website_url"] },
  venue: { table: "venues", name: "name", fields: ["name", "description_de", "address_street", "address_zip", "address_city", "capacity", "website_url", "parking_info_de"] },
};

const RESPONSE_FUNCTION: AiFunctionDeclaration = {
  name: "editorial_research_answer",
  description: "Redaktionelle Antwort mit einzeln prüfbaren Feldvorschlägen.",
  parameters: {
    type: "object",
    properties: {
      answer: { type: "string", description: "Kurze, hilfreiche Antwort auf Deutsch. Widersprüche ausdrücklich nennen." },
      proposals: {
        type: "array",
        items: {
          type: "object",
          properties: {
            field: { type: "string", description: "Exakter Datenbank-Feldname aus der erlaubten Liste." },
            valueJson: { type: "string", description: "Vorgeschlagener Wert als valides JSON, z.B. \"deutsch\", 1987, [\"solist\"] oder null." },
            confidence: { type: "string", enum: ["confirmed", "likely", "unclear"] },
            rationale: { type: "string" },
            sourceUrls: { type: "array", items: { type: "string" } },
          },
          required: ["field", "valueJson", "confidence", "sourceUrls"],
        },
      },
      memorySuggestion: { type: "string", description: "Nur wenn der Nutzer ausdrücklich eine dauerhafte Format-/Stilregel formuliert: die neue vollständige Regel, sonst leer." },
    },
    required: ["answer", "proposals"],
  },
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function bearer(req: Request) { return req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? ""; }

async function within<T>(promise: Promise<T>, milliseconds: number, fallback: T): Promise<T> {
  return await Promise.race([
    promise,
    new Promise<T>((resolve) => setTimeout(() => resolve(fallback), milliseconds)),
  ]);
}

function cleanEditorialText(value: unknown): string {
  let text = String(value ?? "").trim();
  text = text.replace(/^```(?:json|text|markdown)?\s*/i, "").replace(/\s*```$/i, "").trim();
  // Ein als JSON-String zurückgegebenes Textfeld wird exakt einmal
  // dekodiert; dadurch verschwinden Escapezeichen, äußere Quotes und
  // technische Klammerreste, ohne normalen Fließtext zu verändern.
  if (text.startsWith('"') && text.endsWith('"')) {
    try { const decoded = JSON.parse(text); if (typeof decoded === "string") text = decoded; } catch { /* redaktionell weiter bereinigen */ }
  }
  return text
    .replace(/^\s*(?:\[\s*\]|\{\s*\}|\]\[)+\s*/g, "")
    .replace(/\s*(?:\[\s*\]|\{\s*\}|\]\[)+\s*$/g, "")
    .replace(/\]\[/g, "")
    .replace(/^[\s\[\]{}"']+(?=[A-ZÄÖÜ])/u, "")
    .replace(/[\s\[\]{}"']+$/u, "")
    .trim();
}

function isoDate(value: unknown): string {
  const raw = String(value ?? "").trim();
  const german = raw.match(/^(\d{2})\.(\d{2})\.(\d{4})$/);
  const iso = german ? `${german[3]}-${german[2]}-${german[1]}` : raw;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso) || Number.isNaN(new Date(`${iso}T00:00:00Z`).getTime())) {
    throw new Error(`${raw} ist kein vollständiges Datum im Format TT.MM.JJJJ`);
  }
  return iso;
}

function normalizeValue(field: string, value: unknown): unknown {
  if (["birth_date", "death_date"].includes(field)) return isoDate(value);
  if (["founded_year", "member_count", "composition_year", "duration_minutes", "capacity"].includes(field)) {
    const n = Number(value); if (!Number.isFinite(n)) throw new Error(`${field} ist keine Zahl`); return Math.round(n);
  }
  if (["roles", "movements", "alternative_titles"].includes(field)) {
    if (!Array.isArray(value)) throw new Error(`${field} muss eine Liste sein`); return value.map(String);
  }
  if (field === "composer_id") {
    if (value === null) return null;
    if (typeof value !== "string" || !/^[0-9a-f-]{36}$/i.test(value)) throw new Error("Ungültige composer_id");
  }
  if (["biography_de", "description_de", "program_notes_de", "education_career_de", "current_roles_de", "leadership_de", "residency_de", "repertoire_de"].includes(field)) {
    const cleaned = cleanEditorialText(value);
    if (!cleaned) throw new Error(`${field} enthält keinen importierbaren Text`);
    return cleaned;
  }
  return value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type" } });
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const token = bearer(req);
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", { global: { headers: { Authorization: `Bearer ${token}` } } });
  const [{ data: userData }, { data: allowed }] = await Promise.all([userClient.auth.getUser(), userClient.rpc("is_admin_or_editor")]);
  if (!userData.user || allowed !== true) return json({ error: "Nicht berechtigt" }, 403);
  const db = createClient(url, serviceKey);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Ungültiger Request" }, 400); }
  const action = String(body.action ?? "chat");

  if (action === "update_memory") {
    const instructions = String(body.instructions ?? "").trim();
    if (!instructions) return json({ error: "Regelprofil darf nicht leer sein" }, 400);
    const { error } = await db.from("editorial_ai_settings").upsert({ id: true, instructions, updated_at: new Date().toISOString(), updated_by: userData.user.id });
    return error ? json({ error: error.message }, 500) : json({ instructions });
  }

  const entityType = body.entityType as EntityType;
  const entityId = typeof body.entityId === "string" ? body.entityId : "";
  const cfg = CONFIG[entityType];
  if (!cfg || !entityId) return json({ error: "entityType und entityId erforderlich" }, 400);

  if (action === "apply") {
    const proposals = Array.isArray(body.proposals) ? body.proposals as Proposal[] : [];
    const patch: Record<string, unknown> = {};
    for (const p of proposals) if (cfg.fields.includes(p.field) && p.confidence !== "unclear") patch[p.field] = normalizeValue(p.field, p.value);
    if (!Object.keys(patch).length) return json({ error: "Keine sicheren Felder ausgewählt" }, 400);
    const { error } = await db.from(cfg.table).update(patch).eq("id", entityId);
    if (error) return json({ error: error.message }, 500);
    await db.from("system_logs").insert({ action: "editorial_ai_fields_applied", entity_type: entityType, entity_id: entityId, actor: userData.user.id, after: { fields: Object.keys(patch) } });
    return json({ appliedFields: Object.keys(patch) });
  }

  const message = String(body.message ?? "").trim();
  const [{ data: entity, error: entityError }, { data: settings }] = await Promise.all([
    db.from(cfg.table).select(cfg.fields.join(",")).eq("id", entityId).maybeSingle(),
    db.from("editorial_ai_settings").select("instructions").eq("id", true).maybeSingle(),
  ]);
  if (entityError || !entity) return json({ error: "Datensatz nicht gefunden" }, 404);

  let { data: thread } = await db.from("editorial_ai_threads").select("id").eq("entity_type", entityType).eq("entity_id", entityId).eq("created_by", userData.user.id).maybeSingle();
  if (!thread) {
    const created = await db.from("editorial_ai_threads").insert({ entity_type: entityType, entity_id: entityId, created_by: userData.user.id }).select("id").single();
    if (created.error) return json({ error: created.error.message }, 500); thread = created.data;
  }
  const { data: history } = await db.from("editorial_ai_messages").select("role,content,proposals,sources,created_at").eq("thread_id", thread.id).order("created_at").limit(20);
  if (!message) return json({ memory: settings?.instructions ?? "", messages: history ?? [], entity });
  await db.from("editorial_ai_messages").insert({ thread_id: thread.id, role: "user", content: message });

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "GEMINI_API_KEY fehlt" }, 500);
  // Grounding besitzt im Projekt bewusst einen separaten Key/Quota-Bucket.
  // Der normale Generierungs-Key war der Grund für scheinbar erfolgreiche,
  // aber quellenlose Antworten im Redaktionschat.
  const searchApiKey = Deno.env.get("GEMINI_SEARCH_API_KEY") ?? apiKey;
  const name = String((entity as unknown as Record<string, unknown>)[cfg.name] ?? "");
  const research = await researchViaGeminiGrounding(
    searchApiKey,
    `Recherchiere selbstständig und aktuell im Web zur ${entityType}-Entität „${name}“ und beantworte diese redaktionelle Frage: „${message}“. ` +
      `Suche nicht nur nach bereits im Datensatz genannten Webseiten. Verwende mehrere passende Suchanfragen und prüfe Identität/Namensgleichheit. ` +
      `Bevorzuge offizielle Künstler-, Ensemble-, Veranstalter- und Verlagsseiten, danach Kulturinstitutionen und Normdaten; Wikipedia nur ergänzend. ` +
      `Für Personen prüfe insbesondere vollständige Geburts- und Sterbedaten, Nationalität, Ausbildung, Positionen und Instrument. ` +
      `Für Ensembles prüfe Gründung, Sitz, Leitung, Typ und Geschichte; für Werke Komponist, Werkverzeichnis, Entstehung, Sätze, Besetzung und Dauer; ` +
      `für Veranstaltungen offizielle Terminseite, Programm, Mitwirkende und Dauer. Gleiche zentrale Fakten möglichst mit einer zweiten unabhängigen Quelle ab. ` +
      `Nenne zu jeder Tatsachenbehauptung die Quelle. Melde Widersprüche und erfinde nichts. Bekannter Datensatz: ${JSON.stringify(entity)}`,
  );
  const fallbackQueries = [
    `"${name}" Biografie Geburtsdatum Sterbedatum Nationalität`,
    `"${name}" official biography`,
    `"${name}" ${message}`,
  ];
  const needsFallback = !research?.text || research.text.length < 200 || research.sources.length === 0;
  const tavilyKey = Deno.env.get("TAVILY_API_KEY");
  const [tavilyGroups, ddgGroups, wikipedia] = needsFallback ? await within(Promise.all([
    tavilyKey ? Promise.all(fallbackQueries.slice(0, 2).map((q) => searchTavily(tavilyKey, q, 4))) : Promise.resolve([]),
    Promise.all(fallbackQueries.slice(0, 2).map((q) => searchDuckDuckGo(q, 3))),
    entityType === "person" ? fetchWikipediaExtract(name) : Promise.resolve(null),
  ]), 12000, [[], [], null] as [Awaited<ReturnType<typeof searchTavily>>[], Awaited<ReturnType<typeof searchDuckDuckGo>>[], Awaited<ReturnType<typeof fetchWikipediaExtract>>]) : [[], [], null];
  const tavilyResults = tavilyGroups.flatMap((group) => group ?? []);
  const fallbackSources = [
    ...tavilyResults.map((r) => ({ url: r.url, title: r.title })),
    ...ddgGroups.flatMap((group) => group ?? []).map((r) => ({ url: r.url, title: null })),
    ...(wikipedia ? [{ url: wikipedia.pageUrl, title: wikipedia.articleTitle }] : []),
  ];
  const sources = [...new Map([...(research?.sources ?? []), ...fallbackSources].map((s) => [s.url, s])).values()].slice(0, 12);
  // Bei erfolgreichem Grounding liegt der recherchierte Inhalt bereits vor.
  // Zusätzliche Volltextabrufe sind dann redundant und waren der häufigste
  // Grund für eine scheinbar endlose Ladeanzeige.
  const texts = research?.text && research.text.length >= 200 ? [] : (await within(Promise.all(sources.slice(0, 3).map(async (source) => {
    const text = await fetchPageText(source.url);
    return text ? `SEPARAT ABGERUFENE QUELLE ${source.url}\n${text.slice(0, 10000)}` : null;
  })), 10000, [])).filter((text): text is string => text !== null);
  if (wikipedia?.text) texts.push(`WIKIPEDIA-FALLBACK ${wikipedia.pageUrl}\n${wikipedia.text.slice(0, 12000)}`);
  for (const result of tavilyResults.slice(0, 8)) {
    if (result.content) texts.push(`SUCHTREFFER ${result.url}\n${result.content}`);
  }
  const historyText = (history ?? []).slice(-8).map((m: { role: string; content: string }) => `${m.role}: ${m.content}`).join("\n");
  const provider = createGeminiProvider();
  const response = await provider.callFunction(
    `Du bist ein konservativer Recherche-Assistent einer Kulturredaktion. Dauerhaftes Regelprofil:\n${settings?.instructions ?? ""}\n` +
      `Erlaubte Felder: ${cfg.fields.join(", ")}. Schlage ausschließlich diese Felder vor. Nutze nur Fakten aus der Gemini-Webrecherche und den zusätzlich abgerufenen Quellen. ` +
      `WICHTIG: Überführe jede im Recherchetext belegte, profilrelevante Angabe auch in einen eigenen strukturierten Feldvorschlag – nicht nur in den Antworttext. ` +
      `Bei Personen gehören dazu insbesondere roles (freies Textfeld, kleingeschrieben, z.B. komponist/dirigent/solist/chorleiter/moderator/regisseur/schauspieler/choreograf — kein festes Enum mehr, auch andere treffende Rollenbegriffe sind erlaubt), instrument, birth_date, death_date, nationality und biography_de. ` +
      `Geburts- und Sterbedaten nur bei vollständig belegtem Tag, Monat und Jahr als YYYY-MM-DD vorschlagen; niemals aus einem bloßen Jahr den 1. Januar erfinden. ` +
      `Bei Ensembles gehören type, founded_year, member_count, leadership_de, residency_de, repertoire_de und eine redaktionelle Biografie in description_de dazu. ` +
      `Erzeuge Biografien als reinen zusammenhängenden, sachlichen deutschen Fließtext nach dem Regelprofil: kein JSON, keine Markdown-Codeblöcke, keine äußeren Anführungszeichen und keine technischen Klammern. Der Admin bearbeitet und genehmigt jeden Vorschlag vor dem Speichern. ` +
      `sourceUrls dürfen ausschließlich URLs aus der Quellenliste enthalten. Bestehende Werte dürfen korrigiert werden, müssen dann aber besonders gut belegt sein.`,
    `Entität (${entityType}): ${JSON.stringify(entity)}\n\nBisheriger Chat:\n${historyText}\n\nNeue Frage: ${message}` +
      `\n\nVON GEMINI SELBST DURCHGEFÜHRTE GOOGLE-RECHERCHE:\n${research?.text || "Keine Grounding-Antwort verfügbar."}` +
      `\n\nVERWENDETE SUCHANFRAGEN:\n${research?.searchQueries.join("\n") || "nicht ausgewiesen"}` +
      `\n\nZULÄSSIGE QUELLEN-URLS:\n${sources.map((s) => `${s.title ?? "Quelle"}: ${s.url}`).join("\n") || "keine"}` +
      `\n\nZUSÄTZLICH ABGERUFENE VOLLTEXTE:\n${texts.join("\n\n") || "keine"}`,
    RESPONSE_FUNCTION,
  );
  if (!response) return json({ error: "Gemini konnte keine Antwort erzeugen" }, 502);
  const raw = response as Record<string, unknown>;
  let proposals: Proposal[] = Array.isArray(raw.proposals) ? raw.proposals.flatMap((p: any) => {
    if (!cfg.fields.includes(p.field)) return [];
    try {
      let value = JSON.parse(p.valueJson);
      if (["biography_de", "description_de", "program_notes_de", "education_career_de", "current_roles_de", "leadership_de", "residency_de", "repertoire_de"].includes(p.field)) value = cleanEditorialText(value);
      if (!value && value !== 0 && value !== false) return [];
      return [{ field: p.field, value, confidence: p.confidence, rationale: cleanEditorialText(p.rationale), sourceUrls: p.sourceUrls ?? [] } as Proposal];
    } catch { return []; }
  }) : [];
  const answer = cleanEditorialText(raw.answer ?? "Keine belastbare Antwort gefunden.");
  // Sicherheitsnetz: Manche Gemini-Antworten liefern eine vollständige
  // Biografie im Antworttext, vergessen aber trotz Function-Schema den
  // parallelen biography_de/description_de-Vorschlag. Der Text soll dann
  // nicht in einer Sackgasse enden, sondern weiterhin redaktionell
  // bearbeitbar und genehmigungspflichtig angeboten werden.
  const biographyField = entityType === "person"
    ? "biography_de"
    : entityType === "ensemble" || entityType === "venue"
    ? "description_de"
    : null;
  if (biographyField && /bio(?:graf|graph)|lebenslauf|portrait/i.test(message) && !proposals.some((p) => p.field === biographyField) && answer.length >= 120) {
    proposals = [...proposals, {
      field: biographyField,
      value: answer,
      confidence: sources.length >= 2 ? "confirmed" : "likely",
      rationale: "Aus der recherchierten Antwort als redaktionell bearbeitbarer Biografievorschlag übernommen.",
      sourceUrls: sources.map((source) => source.url).slice(0, 5),
    }];
  }
  if (entityType === "person" && !proposals.some((p) => p.field === "roles")) {
    const roleTerms: Array<[RegExp, string]> = [[/\bKomponist(?:in)?\b/i, "komponist"], [/\bDirigent(?:in)?\b/i, "dirigent"], [/\b(?:Solist|Solistin)\b/i, "solist"], [/\bChorleiter(?:in)?\b/i, "chorleiter"], [/\bModerator(?:in)?\b/i, "moderator"]];
    const roles = roleTerms.filter(([pattern]) => pattern.test(answer)).map(([, role]) => role);
    if (roles.length) proposals = [...proposals, { field: "roles", value: roles, confidence: "likely", rationale: "Aus den im recherchierten Text ausdrücklich genannten Tätigkeiten erkannt.", sourceUrls: sources.map((source) => source.url).slice(0, 5) }];
  }
  await db.from("editorial_ai_messages").insert({ thread_id: thread.id, role: "assistant", content: answer, proposals, sources });
  await db.from("editorial_ai_threads").update({ updated_at: new Date().toISOString() }).eq("id", thread.id);
  return json({ answer, proposals, sources, memorySuggestion: raw.memorySuggestion ?? null });
});
