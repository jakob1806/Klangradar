// Nutzerwunsch: "bei jeder venue, person, ensemble und veranstaltung fehlt
// nach wie vor der button, dass mithilfe von KI daten automatisch
// ausgefüllt werden können. z.b. Geburtsdatum, sterbedatum, rolle,
// instrument, website, programmtext, dauer der veranstaltung usw." — die
// bestehenden enrich-person-profile/enrich-venue-details/enrich-ensemble-
// profile/enrich-event-references-Functions laufen NUR als Batch-Cron
// (POST {limit}), wählen ihre Kandidaten selbst aus und decken diese
// konkret genannten Felder teils gar nicht ab (birth_date/death_date/
// instrument/website_url fehlten komplett). Diese Function ist der fehlende
// GEZIELTE Einzel-Aufruf für GENAU eine Entität — für den neuen "Prüfen &
// Ergänzen"-Button auf den vier Detailseiten.
//
// Gleiche Grundprinzipien wie jede andere Anreicherungs-Function in diesem
// Projekt: nur leere Felder befüllen (nie eine bestehende, ggf.
// redaktionell gepflegte Angabe überschreiben), Provenienz pro Feld via
// _shared/provenance.ts, konservative KI-Extraktion ("nicht erfinden").
//
// Quelle: eigene website_url falls vorhanden, sonst Websuche (DuckDuckGo
// zuerst ohne Key, Gemini-Grounding als Ergänzung — dasselbe bereits
// erprobte Muster wie in auto-fix-content-report/enrich-entity-images),
// bei Personen zusätzlich Wikipedia-Fallback (fetchWikipediaExtract) —
// insbesondere für Geburts-/Sterbedatum historischer Persönlichkeiten oft
// die einzige verfügbare Quelle.
//
// Aufruf: POST { entityType: "person"|"venue"|"ensemble"|"event", entityId }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchPageText } from "../_shared/pageText.ts";
import { fetchWikipediaExtract } from "../_shared/wikipediaExtract.ts";
import { searchDuckDuckGo } from "../_shared/duckDuckGoSearch.ts";
import { searchViaGeminiGrounding } from "../_shared/geminiGroundedSearch.ts";
import { recordFieldSources, type FieldSource } from "../_shared/provenance.ts";
import { researchBiographyFromKnowledge } from "../_shared/bioResearch.ts";

type EntityType = "person" | "venue" | "ensemble" | "event";

const TABLE: Record<EntityType, string> = {
  person: "persons",
  venue: "venues",
  ensemble: "ensembles",
  event: "events",
};

function isValidHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

/** Sucht (kostenfrei zuerst) eine offizielle Website für `name`, falls die
 * Entität noch keine hat — probiert Kandidaten der Reihe nach, bis eine
 * tatsächlich abrufbaren Text liefert. Gibt null, wenn nichts brauchbares
 * gefunden wurde.
 *
 * Live-Diagnose (2026-08-09): beide Quellen können unabhängig voneinander
 * leer laufen — DuckDuckGos HTML-Endpunkt liefert von Supabase-Cloud-IPs
 * aus teils 0 Treffer (kein Fehler, einfach eine leere Ergebnisliste), das
 * gemeinsam genutzte GEMINI_SEARCH_API_KEY-Kontingent kann durch andere
 * Funktionen (Bilder-Recherche) bereits ausgeschöpft sein (HTTP 429). Für
 * Personen fängt der Wikipedia-Fallback (siehe Aufrufer) diesen Fall meist
 * ab; bei Venues/Ensembles ohne eigene website_url bleibt es dann bei
 * status "no_change" statt eines Fehlers — kein Absturz, aber keine
 * Garantie auf Erfolg bei jedem Klick. */
async function discoverWebsite(
  name: string,
  context: string,
): Promise<{ url: string; pageText: string } | null> {
  const query = `${name} ${context} offizielle Website`;
  const candidates: string[] = [];

  const ddgResults = await searchDuckDuckGo(query, 3);
  for (const r of ddgResults ?? []) candidates.push(r.url);

  const geminiApiKey = Deno.env.get("GEMINI_SEARCH_API_KEY");
  if (geminiApiKey && candidates.length < 3) {
    const groundedResults = await searchViaGeminiGrounding(geminiApiKey, query);
    for (const r of groundedResults ?? []) candidates.push(r.url);
  }

  for (const candidateUrl of candidates.slice(0, 3)) {
    if (!isValidHttpUrl(candidateUrl)) continue;
    const text = await fetchPageText(candidateUrl);
    if (text) return { url: candidateUrl, pageText: text };
  }
  return null;
}

interface FilledField {
  field: string;
  value: unknown;
}

interface EnrichResult {
  status: "filled" | "no_change" | "error";
  diagnosis: string;
  filledFields: FilledField[];
}

const PERSON_FUNCTION: AiFunctionDeclaration = {
  name: "extract_person_details",
  description: "Aus dem bereitgestellten Text erkannte, wörtlich belegte Profildaten einer Musikerin/eines Musikers.",
  parameters: {
    type: "object",
    properties: {
      birthDate: { type: "string", description: "Geburtsdatum als YYYY-MM-DD (oder nur YYYY, falls nur das Jahr bekannt ist), NUR wenn im Text explizit genannt." },
      deathDate: { type: "string", description: "Sterbedatum als YYYY-MM-DD (oder nur YYYY), NUR wenn im Text explizit genannt und die Person verstorben ist." },
      instrument: { type: "string", description: "Hauptinstrument, z.B. 'Violine', 'Klavier', 'Dirigat' — NUR wenn im Text eindeutig genannt." },
      roles: {
        type: "array",
        items: { type: "string", enum: ["komponist", "dirigent", "solist", "chorleiter", "moderator"] },
        description: "Berufliche Rollen NUR aus dieser festen Liste, NUR wenn im Text eindeutig belegt (z.B. 'komponist' bei einem Komponisten, 'dirigent' bei einer Dirigentin).",
      },
      biographyDe: { type: "string", description: "Kurzbiografie auf Deutsch (2-4 Sätze), NUR aus dem Text, keine erfundenen Details." },
      nationality: { type: "string", description: "Staatsangehörigkeit als Adjektiv in Grundform, z.B. 'russisch', 'deutsch', 'französisch' — NUR wenn im Text genannt." },
    },
    required: [],
  },
};

const VENUE_FUNCTION: AiFunctionDeclaration = {
  name: "extract_venue_details",
  description: "Aus dem bereitgestellten Text erkannte, wörtlich belegte Informationen zu einem Konzertsaal/einer Spielstätte.",
  parameters: {
    type: "object",
    properties: {
      descriptionDe: { type: "string", description: "Kurzbeschreibung auf Deutsch (2-4 Sätze), NUR aus dem Text." },
      historyDe: { type: "string", description: "Geschichte des Hauses auf Deutsch, NUR wenn im Text genannt." },
      capacity: { type: "number", description: "Sitzplatzkapazität als Zahl, NUR wenn im Text explizit genannt." },
    },
    required: [],
  },
};

const ENSEMBLE_FUNCTION: AiFunctionDeclaration = {
  name: "extract_ensemble_details",
  description: "Aus dem bereitgestellten Text erkannte, wörtlich belegte Informationen zu einem Ensemble/Orchester/Chor.",
  parameters: {
    type: "object",
    properties: {
      descriptionDe: { type: "string", description: "Kurzbeschreibung auf Deutsch (2-4 Sätze), NUR aus dem Text." },
      foundedYear: { type: "number", description: "Gründungsjahr als Zahl, NUR wenn im Text explizit genannt." },
      memberCount: { type: "number", description: "Anzahl Mitglieder als Zahl, NUR wenn im Text explizit genannt." },
    },
    required: [],
  },
};

const EVENT_FUNCTION: AiFunctionDeclaration = {
  name: "extract_event_details",
  description: "Aus dem bereitgestellten Text erkannte, wörtlich belegte Informationen zu einer Konzertveranstaltung.",
  parameters: {
    type: "object",
    properties: {
      programNotesDe: { type: "string", description: "Programmtext/Werkübersicht auf Deutsch, NUR aus dem Text, keine erfundenen Werke." },
      durationMinutes: { type: "number", description: "Gesamtdauer der Veranstaltung in Minuten (inkl. Pause, falls genannt), NUR wenn im Text explizit genannt." },
      descriptionDe: { type: "string", description: "Kurzbeschreibung der Veranstaltung auf Deutsch, NUR aus dem Text." },
    },
    required: [],
  },
};

Deno.serve(async (req) => {
  if (!hasAnyAiProviderConfigured()) {
    return new Response(JSON.stringify({ error: "Kein AI-Provider-Secret gesetzt" }), { status: 500 });
  }

  let body: { entityType?: unknown; entityId?: unknown };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Ungültiger Request-Body" }), { status: 400 });
  }

  const entityType = body.entityType as EntityType | undefined;
  const entityId = typeof body.entityId === "string" ? body.entityId : null;
  if (!entityType || !TABLE[entityType] || !entityId) {
    return new Response(JSON.stringify({ error: "entityType und entityId sind erforderlich" }), { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const result = await enrichEntity(supabase, entityType, entityId);
  return new Response(JSON.stringify(result));
});

async function enrichEntity(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entityType: EntityType,
  entityId: string,
): Promise<EnrichResult> {
  const table = TABLE[entityType];
  const { data: entity, error } = await supabase.from(table).select("*").eq("id", entityId).maybeSingle();
  if (error || !entity) {
    return { status: "error", diagnosis: `Entität nicht ladbar: ${error?.message ?? "nicht gefunden"}`, filledFields: [] };
  }

  // 1. Quelle beschaffen: eigene website_url zuerst, sonst Websuche, bei
  // Personen zusätzlich Wikipedia — je nach Entitätstyp unterschiedliche
  // "Name"-Spalte und Ortskontext für die Suchanfrage.
  const name: string = entityType === "person" ? entity.full_name : entityType === "event" ? entity.title : entity.name;

  // Für eine fehlende Personenbiografie zuerst der schnelle direkte
  // Wissenspfad — wie eine normale Gemini-Abfrage, ohne Website- oder
  // Wikipedia-Wartezeit. Weitere strukturierte Felder können bei einem
  // späteren Lauf weiterhin quellenbasiert ergänzt werden.
  if (entityType === "person" && !entity.biography_de) {
    const context = [
      Array.isArray(entity.roles) && entity.roles.length ? `Rollen: ${entity.roles.join(", ")}` : null,
      entity.instrument ? `Instrument/Stimmfach: ${entity.instrument}` : null,
      entity.nationality ? `Nationalität: ${entity.nationality}` : null,
    ].filter(Boolean).join("; ");
    const knowledge = await researchBiographyFromKnowledge("person", name, context || null);
    if (knowledge?.biography) {
      const { error: biographyError } = await supabase.from("persons").update({
        biography_de: knowledge.biography,
        ai_biography_status: "generated",
        ai_biography_checked_at: new Date().toISOString(),
        ai_biography_error: null,
      }).eq("id", entityId).is("biography_de", null);
      if (biographyError) {
        return { status: "error", diagnosis: `Biografie konnte nicht gespeichert werden: ${biographyError.message}`, filledFields: [] };
      }
      await recordFieldSources(supabase, [{
        entityType: "person",
        entityId,
        fieldName: "biography_de",
        sourceUrl: null,
        sourceName: "KI-Wissen (direkte Abfrage, ohne Webabruf)",
        confidence: "likely",
      }]);
      return {
        status: "filled",
        diagnosis: "Biografie direkt aus KI-Wissen erstellt; kein Wikipedia- oder Website-Abruf nötig.",
        filledFields: [{ field: "biography_de", value: knowledge.biography }],
      };
    }
  }
  let pageUrl: string | null = entityType === "event" ? (entity.ticket_url ?? entity.website_url) : entity.website_url;
  let pageText: string | null = null;
  let sourceLabel = "eigene Website";
  let discoveredWebsiteUrl: string | null = null;

  if (pageUrl) {
    pageText = await fetchPageText(pageUrl);
  }

  if (!pageText && entityType !== "event") {
    const context = entityType === "person" ? "Musiker Klassik" : "München";
    const found = await discoverWebsite(name, context);
    if (found) {
      pageUrl = found.url;
      pageText = found.pageText;
      sourceLabel = "per Websuche gefundene Website";
      if (!entity.website_url) discoveredWebsiteUrl = found.url;
    }
  } else if (!pageText && entityType === "event") {
    const venueName = entity.venue_id ? (await supabase.from("venues").select("name").eq("id", entity.venue_id).maybeSingle()).data?.name : null;
    const found = await discoverWebsite(name, [venueName, "München", "Konzert"].filter(Boolean).join(" "));
    if (found) {
      pageUrl = found.url;
      pageText = found.pageText;
      sourceLabel = "per Websuche gefundene Seite";
    }
  }

  let wikipediaFallback = false;
  if (!pageText && entityType === "person") {
    const extract = await fetchWikipediaExtract(name);
    if (extract) {
      pageUrl = extract.pageUrl;
      pageText = extract.text;
      sourceLabel = "Wikipedia";
      wikipediaFallback = true;
    }
  }

  if (!pageText) {
    return {
      status: "no_change",
      diagnosis: "Keine Quelle gefunden (weder eigene Website noch Websuche" +
        (entityType === "person" ? " noch Wikipedia" : "") + ") — keine Felder befüllt.",
      filledFields: discoveredWebsiteUrl
        ? [{ field: "website_url", value: discoveredWebsiteUrl }]
        : [],
    };
  }

  const fnDeclaration = entityType === "person"
    ? PERSON_FUNCTION
    : entityType === "venue"
    ? VENUE_FUNCTION
    : entityType === "ensemble"
    ? ENSEMBLE_FUNCTION
    : EVENT_FUNCTION;

  const response = await callAiFunction(
    "Du bist Teil einer redaktionellen Datenpflege für eine Klassik-Konzert-App in München. Extrahiere NUR " +
      "Informationen, die WÖRTLICH oder eindeutig im bereitgestellten Text stehen. Erfinde niemals Werte, " +
      "lasse ein Feld weg statt zu raten.",
    `Name: ${name}\nQuelle (${sourceLabel}): ${pageUrl}\n\nText:\n${pageText}`,
    fnDeclaration,
  );

  if (!response) {
    return {
      status: "error",
      diagnosis: "KI-Aufruf fehlgeschlagen (alle Provider).",
      filledFields: discoveredWebsiteUrl ? [{ field: "website_url", value: discoveredWebsiteUrl }] : [],
    };
  }

  const { args, provider } = response;
  const updates: Record<string, unknown> = {};
  const filledFields: FilledField[] = [];
  const sources: FieldSource[] = [];
  const confidence = wikipediaFallback ? "likely" : "confirmed";

  function isEmpty(value: unknown): boolean {
    return value === null || value === undefined || value === "" || (Array.isArray(value) && value.length === 0);
  }

  function maybeSet(schemaField: string, column: string, transform?: (v: unknown) => unknown) {
    if (!isEmpty(entity[column])) return; // nie überschreiben
    const raw = args[schemaField];
    if (raw === undefined || raw === null || raw === "") return;
    const value = transform ? transform(raw) : raw;
    if (value === null || value === undefined) return;
    updates[column] = value;
    filledFields.push({ field: column, value });
    sources.push({ entityType, entityId, fieldName: column, sourceUrl: pageUrl, sourceName: sourceLabel, confidence });
  }

  if (discoveredWebsiteUrl) {
    updates.website_url = discoveredWebsiteUrl;
    filledFields.push({ field: "website_url", value: discoveredWebsiteUrl });
    sources.push({ entityType, entityId, fieldName: "website_url", sourceUrl: discoveredWebsiteUrl, sourceName: "Websuche", confidence: "likely" });
  }

  if (entityType === "person") {
    maybeSet("birthDate", "birth_date", (v) => normalizeDate(String(v)));
    maybeSet("deathDate", "death_date", (v) => normalizeDate(String(v)));
    maybeSet("instrument", "instrument");
    maybeSet("roles", "roles", (v) => {
      const valid = new Set(["komponist", "dirigent", "solist", "chorleiter", "moderator"]);
      const filtered = (Array.isArray(v) ? v : []).map((r) => String(r).toLowerCase()).filter((r) => valid.has(r));
      return filtered.length > 0 ? filtered : null;
    });
    maybeSet("biographyDe", "biography_de");
    maybeSet("nationality", "nationality");
  } else if (entityType === "venue") {
    maybeSet("descriptionDe", "description_de");
    maybeSet("historyDe", "history_de");
    maybeSet("capacity", "capacity");
  } else if (entityType === "ensemble") {
    maybeSet("descriptionDe", "description_de");
    maybeSet("foundedYear", "founded_year");
    maybeSet("memberCount", "member_count");
  } else {
    maybeSet("programNotesDe", "program_notes_de");
    maybeSet("durationMinutes", "duration_minutes");
    maybeSet("descriptionDe", "description_de");
  }

  if (Object.keys(updates).length === 0) {
    return {
      status: "no_change",
      diagnosis: `Quelle (${sourceLabel}) abgerufen, aber alle relevanten Felder sind bereits befüllt oder der Text lieferte nichts Neues.`,
      filledFields: [],
    };
  }

  const { error: updateError } = await supabase.from(table).update(updates).eq("id", entityId);
  if (updateError) {
    return { status: "error", diagnosis: `Update fehlgeschlagen: ${updateError.message}`, filledFields: [] };
  }

  await recordFieldSources(supabase, sources);

  return {
    status: "filled",
    diagnosis: `${filledFields.length} Feld(er) aus ${sourceLabel} befüllt (KI-Provider: ${provider}).`,
    filledFields,
  };
}

/** Normalisiert ein von der KI geliefertes Datum auf YYYY-MM-DD (nur Jahr
 * bekannt -> 1. Januar dieses Jahres, damit die date-Spalte gültig bleibt,
 * mit entsprechend niedrigerer Konfidenz in der Provenienz-Zeile). */
function normalizeDate(raw: string): string | null {
  const isoMatch = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (isoMatch) return isoMatch[0];
  const yearOnly = raw.match(/^(\d{4})$/);
  if (yearOnly) return `${yearOnly[1]}-01-01`;
  return null;
}
