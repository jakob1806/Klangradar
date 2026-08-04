// Reichert bestehende Events nachträglich mit Komponisten/Werken/Mitwirkenden
// an: liest title+description_de, schickt sie an die Gemini API (dasselbe
// forced-function-call-Muster wie extract-event-from-url/llm.ts), matcht die
// erkannten Namen gegen persons/ensembles/works (case-insensitive exact
// match — bewusst kein Fuzzy-Matching, um keine unterschiedlichen Personen
// versehentlich zusammenzulegen) und verknüpft über event_works /
// event_participants. Unbekannte Personen/Ensembles werden NICHT mehr
// direkt angelegt (das passierte hier früher ungeprüft) — sie landen als
// entity_candidates zur redaktionellen Freigabe
// (20260818000004_entity_candidates.sql); die event_participants-
// Verknüpfung für so einen Act folgt erst nach Freigabe bei einem
// erneuten Lauf. Komponisten von Werken bleiben davon unberührt: ein noch
// nicht bestätigter Komponistenname führt nur zu einem Werk ohne
// composer_id (composer_id ist ohnehin nullable), keine Sonderbehandlung
// nötig.
//
// Verlinkt zusätzlich event_genres — im Gegensatz zu tags (freie
// KI-Schlagworte) ist genres ein kontrolliertes Vokabular (genre_type-Enum,
// 20260715000002_enums_and_lookup.sql): die KI wählt nur aus der festen
// Liste, es wird nie eine neue genres-Zeile angelegt. War vorher nur über
// das Admin-Eventformular manuell zuweisbar, keine Ingestion setzte je
// event_genres automatisch.
//
// Beim Anlegen eines neuen Kandidaten wird zusätzlich per Tavily (siehe
// _shared/tavily.ts) nach dem Namen gesucht und der Treffer per LLM zu
// einer kurzen Einordnung (Bio-Snippet, Website) zusammengefasst — landet
// in discovery_context.tavily und gibt dem Redakteur im Review mehr als
// nur den nackten Namen. Rein additiv: fehlt TAVILY_API_KEY oder schlägt
// die Suche fehl, wird der Kandidat trotzdem ganz normal ohne Anreicherung
// angelegt.
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 20)
// scheduled Events, die noch keine event_works/event_participants-Zeile
// haben. Mehrfacher Aufruf nötig, um alle 238 Events abzudecken (Edge
// Function Zeitlimit).
//
// Nutzt die AI-Provider-Fallback-Kette aus _shared/ai/router.ts statt eines
// fest hinterlegten einzelnen Providers — siehe dort für die Begründung.
// Braucht mindestens eines der dort verdrahteten Provider-Secrets
// (CEREBRAS_API_KEY, NVIDIA_API_KEY, GEMINI_API_KEY) und optional
// TAVILY_API_KEY (siehe _shared/tavily.ts) für die Kandidaten-Anreicherung.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { logSystemAction } from "../_shared/systemLog.ts";
import { enrichCandidateContext } from "../_shared/entityEnrichment.ts";
import { fetchPageText } from "../_shared/pageText.ts";
import { recordFieldSource } from "../_shared/provenance.ts";

// Muss exakt dem genre_type-Enum entsprechen (20260715000002_enums_and_lookup.sql)
// — eine feste, kuratierte Liste statt Freitext wie bei tags, damit
// event_genres ein kontrolliertes Vokabular bleibt.
const GENRE_SLUGS = [
  "oper", "konzert", "chormusik", "kirchenmusik", "kammermusik",
  "liederabend", "orchester", "orgel", "jazz", "neue_musik",
  "familienkonzert", "kinder",
];

const ENRICH_FUNCTION: AiFunctionDeclaration = {
  name: "extract_references",
  description: "Aus Titel+Beschreibung eines Konzerts erkannte Komponisten, Werke und Mitwirkende.",
  parameters: {
    type: "object",
    properties: {
      works: {
        type: "array",
        description:
          "Nur konkrete, benannte Werke (z. B. 'Symphonie Nr. 5', 'Matthäus-Passion'). " +
          "KEINEN Eintrag erzeugen, wenn nur ein Komponisten-Nachname ohne erkennbares " +
          "spezifisches Werk im Text steht — dann leer lassen statt zu raten. " +
          "Reihenfolge der Einträge MUSS der Reihenfolge entsprechen, in der die Werke im " +
          "Text genannt werden (das ist die tatsächliche Konzert-/Programmreihenfolge) — " +
          "niemals alphabetisch oder nach Bekanntheit umsortieren. " +
          "WICHTIG gegen Duplikate: Texte erwähnen dasselbe Werk oft MEHRFACH (z. B. kurz " +
          "in einer werbenden Einleitung UND danach nochmal ausführlich in einer formalen " +
          "Programmliste, oder ein Spitzname wie 'Tragische' UND der volle Titel " +
          "'Sinfonie Nr. 4 c-Moll »Tragische«' an anderer Stelle im selben Text). Das ist " +
          "IMMER ein einziges Werk — dafür GENAU EINEN Eintrag erzeugen, nie mehrere. Bei " +
          "mehreren Erwähnungen desselben Werks die Version mit den meisten Informationen " +
          "verwenden (vollständigster Titel, Komponist, Opus-/Werkverzeichnisnummer, Tonart).",
        items: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description:
                "NUR der Werktitel selbst (z. B. 'Symphonie Nr. 5 c-Moll'). Den " +
                "Komponistennamen NIEMALS in dieses Feld mit aufnehmen, auch wenn er im " +
                "Text unmittelbar vor dem Werktitel steht ('Beethoven: Symphonie Nr. 5' " +
                "→ title ist NUR 'Symphonie Nr. 5', der Name gehört ausschließlich in " +
                "composerName) — die Anwendung zeigt Komponist und Werktitel getrennt an.",
            },
            composerName: {
              type: "string",
              description: "Voller Name des Komponisten, falls erkennbar (z. B. 'Johannes Brahms'), sonst weglassen.",
            },
            catalogNumber: {
              type: "string",
              description:
                "Opus-/Werkverzeichnisnummer NUR, wenn wortwörtlich im Text steht (z. B. 'op. 68', 'KV 550', " +
                "'BWV 244'). Niemals aus dem Werktitel ableiten oder aus allgemeinem Wissen ergänzen — lieber " +
                "weglassen als raten.",
            },
            keySignature: {
              type: "string",
              description: "Tonart NUR, wenn wortwörtlich im Text steht (z. B. 'c-Moll'), sonst weglassen.",
            },
          },
          required: ["title"],
        },
      },
      participants: {
        type: "array",
        description:
          "Auftretende Personen/Ensembles. NIEMALS Ticketing-Agenturen, Konzertdirektionen, " +
          "Veranstalter-GmbHs oder Spielstätten hier eintragen (z. B. 'MünchenMusik GmbH & Co. KG', " +
          "'Bell' Arte Konzertdirektion' sind KEINE Mitwirkenden) — nur echte Musiker/Ensembles.",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            type: { type: "string", enum: ["person", "ensemble"] },
            role: {
              type: "string",
              enum: ["komponist", "dirigent", "solist", "chorleiter", "moderator"],
              description: "Nur setzen, wenn im Text erkennbar; sonst weglassen (z. B. ein einfach mitspielendes Orchester).",
            },
            ensembleType: {
              type: "string",
              enum: ["chor", "orchester", "kammerensemble", "big_band", "sonstiges"],
              description: "Nur bei type=ensemble relevant, sonst weglassen.",
            },
            instrument: { type: "string", description: "Falls im Text erkennbar, sonst weglassen." },
          },
          required: ["name", "type"],
        },
      },
      tags: {
        type: "array",
        description:
          "1-5 kurze, wiederverwendbare Schlagworte auf Deutsch (z. B. 'Barock', 'Familienkonzert', 'Orgel', " +
          "'A-cappella', 'Uraufführung'). KEINE Komponisten-/Werktitel-Wiederholungen aus works/participants, " +
          "keine Venue-/Datumsangaben — nur Stichworte, die ein Nutzer als Filter/Suchbegriff nutzen würde. " +
          "Leeres Array, wenn nichts Spezifisches erkennbar ist.",
        items: { type: "string" },
      },
      genres: {
        type: "array",
        description:
          "IMMER mindestens 1, maximal 2 Kategorien aus der FESTEN Liste (nicht erfinden, nur aus dieser Liste " +
          "wählen): oper, konzert, chormusik, kirchenmusik, kammermusik, liederabend, orchester, orgel, jazz, " +
          "neue_musik, familienkonzert, kinder. Wenn nichts Spezifischeres eindeutig erkennbar ist (z. B. kein " +
          "Chor/Kirche/Kammermusik-Hinweis im Text), 'konzert' als generische Kategorie wählen — jedes " +
          "klassische Konzert passt mindestens dort hinein. NUR ein leeres Array, wenn Titel/Beschreibung gar " +
          "keine Veranstaltung beschreiben (z. B. reiner Terminhinweis ohne jeden inhaltlichen Bezug).",
        items: {
          type: "string",
          enum: GENRE_SLUGS,
        },
      },
      doorsInfo: {
        type: "string",
        description:
          "Einlasszeit/-hinweis NUR, wenn wortwörtlich im Text steht (z. B. 'Einlass 19:00 Uhr', 'Einlass ab " +
          "18:30'), sonst weglassen. Nicht aus der Konzertbeginn-Uhrzeit ableiten.",
      },
      estimatedDurationMinutes: {
        type: "number",
        description:
          "Voraussichtliche Gesamtdauer in Minuten NUR, wenn im Text explizit genannt (z. B. 'Dauer: ca. 90 " +
          "Minuten', 'ca. 2 Stunden inkl. Pause'), sonst weglassen. Niemals aus der Werkliste schätzen.",
      },
      hasIntermission: {
        type: "boolean",
        description:
          "true/false NUR, wenn im Text explizit eine Pause erwähnt oder explizit ausgeschlossen wird (z. B. " +
          "'mit Pause', 'ohne Pause', 'keine Pause'), sonst ganz weglassen (kein Rateergebnis).",
      },
      longDescription: {
        type: "string",
        description:
          "Eine redaktionelle Kurzbeschreibung der Veranstaltung auf Deutsch (2-4 Sätze), NUR aus Informationen, " +
          "die tatsächlich im bereitgestellten Text stehen (Programmidee, Anlass, Besonderheiten) — keine " +
          "Floskeln, keine erfundenen Zusatzinformationen. Weglassen, wenn der Text dafür nicht genug hergibt.",
      },
      targetAudience: {
        type: "string",
        description:
          "Zielgruppe NUR, wenn im Text explizit genannt (z. B. 'Familienkonzert ab 6 Jahren', 'für " +
          "Kinder ab 4 Jahren'), sonst weglassen.",
      },
      language: {
        type: "string",
        description:
          "Aufführungssprache/Übertitel-Hinweis NUR, wenn im Text explizit genannt (z. B. 'in italienischer " +
          "Sprache mit deutschen Übertiteln'), sonst weglassen.",
      },
    },
    required: ["works", "participants", "genres"],
  },
};

interface EventRow {
  id: string;
  title: string;
  description_de: string | null;
  website_url: string | null;
  ticket_url: string | null;
  doors_info: string | null;
  duration_minutes: number | null;
  has_intermission: boolean | null;
  target_audience: string | null;
  performance_language: string | null;
}

interface ExtractedReferences {
  works: Array<{ title: string; composerName: string | null; catalogNumber: string | null; keySignature: string | null }>;
  participants: Array<
    { name: string; type: string; role: string | null; ensembleType: string | null; instrument: string | null }
  >;
  tags: string[];
  genres: string[];
  doorsInfo: string | null;
  estimatedDurationMinutes: number | null;
  hasIntermission: boolean | null;
  longDescription: string | null;
  targetAudience: string | null;
  language: string | null;
}

/** Erkennt Platzhalter-"Namen" aus Besetzungslisten, die keine echte Person/
 * kein echtes Ensemble bezeichnen: "N.N." (nomen nescio, noch unbestimmt),
 * einzelne Initialen ("J", "J."), "TBA"/"TBD"/"o. A."/"unbekannt". */
function isPlaceholderName(name: string): boolean {
  const trimmed = name.trim();
  if (!trimmed) return true;
  if (/^n\.?\s*n\.?$/i.test(trimmed)) return true;
  if (/^[a-zà-ÿ]\.?$/i.test(trimmed)) return true;
  if (/^(tba|tbd|t\.\s*b\.\s*a\.?|t\.\s*b\.\s*d\.?|o\.\s*a\.?|unbekannt|n\/a|k\.\s*a\.?)$/i.test(trimmed)) return true;
  return false;
}

/** `pageText` ist der bereinigte Volltext der offiziellen Event-Seite
 * (siehe _shared/pageText.ts), falls verfügbar — deutlich reichhaltiger
 * als title+description_de allein (Opus/Werkverzeichnis, Einlasszeit,
 * ausführliche Beschreibung stehen oft nur dort). Optional, da nicht jedes
 * Event eine abrufbare website_url/ticket_url hat; die Extraktion fällt
 * dann auf title+description_de zurück wie bisher. */
async function extractReferences(
  title: string,
  description: string | null,
  pageText: string | null,
): Promise<ExtractedReferences | null> {
  const text = `Titel: ${title}${description ? `\nBeschreibung: ${description}` : ""}` +
    (pageText ? `\n\nVolltext der offiziellen Veranstaltungsseite:\n${pageText}` : "");

  const response = await callAiFunction(
    "Du extrahierst Komponisten, Werke, Mitwirkende und praktische Details aus Titel/Beschreibung " +
      "(und, falls vorhanden, dem Volltext der offiziellen Veranstaltungsseite) eines klassischen Konzerts. " +
      "Sei konservativ: lieber ein leeres Feld/Array als geraten. Erfinde NIEMALS Informationen, die nicht " +
      "wortwörtlich im bereitgestellten Text stehen.",
    text,
    ENRICH_FUNCTION,
  );
  const args = response?.args;
  if (!args) return null;

  // Live beobachtet: das Modell klassifiziert eine Opus-/Werkverzeichnis-
  // nummer (z. B. "op. 21") gelegentlich fälschlich als keySignature statt
  // catalogNumber (und umgekehrt eine Tonart als catalogNumber). Beide
  // Felder haben ein erkennbares Muster (Opus/BWV/KV/Hob./WoO-Präfix vs.
  // "-Dur"/"-Moll"-Suffix) — hier vertauschen statt die falsche Zuordnung
  // unkorrigiert zu übernehmen.
  const CATALOG_PATTERN = /^(op\.?|opus|bwv|kv|k\.?v\.?|hob\.?|woo|d\.?)\s?\d/i;
  const KEY_SIGNATURE_PATTERN = /-(dur|moll)\b/i;
  const works = Array.isArray(args.works)
    ? args.works.map((w: Record<string, unknown>) => {
      let catalogNumber = typeof w.catalogNumber === "string" ? w.catalogNumber : null;
      let keySignature = typeof w.keySignature === "string" ? w.keySignature : null;
      if (catalogNumber && KEY_SIGNATURE_PATTERN.test(catalogNumber) && !CATALOG_PATTERN.test(catalogNumber)) {
        [catalogNumber, keySignature] = [keySignature, catalogNumber];
      } else if (keySignature && CATALOG_PATTERN.test(keySignature) && !KEY_SIGNATURE_PATTERN.test(keySignature)) {
        [catalogNumber, keySignature] = [keySignature, catalogNumber];
      }
      return {
        title: typeof w.title === "string" ? w.title : "",
        composerName: typeof w.composerName === "string" ? w.composerName : null,
        catalogNumber,
        keySignature,
      };
    })
    : [];
  const participants = Array.isArray(args.participants) ? args.participants : [];
  const tags = Array.isArray(args.tags) ? args.tags.filter((t: unknown) => typeof t === "string" && t.trim()) : [];
  const genres = Array.isArray(args.genres)
    ? args.genres.filter((g: unknown) => typeof g === "string" && GENRE_SLUGS.includes(g))
    : [];
  return {
    works,
    participants,
    tags,
    genres,
    doorsInfo: typeof args.doorsInfo === "string" && args.doorsInfo.trim() ? args.doorsInfo.trim() : null,
    estimatedDurationMinutes: typeof args.estimatedDurationMinutes === "number" ? args.estimatedDurationMinutes : null,
    hasIntermission: typeof args.hasIntermission === "boolean" ? args.hasIntermission : null,
    longDescription: typeof args.longDescription === "string" && args.longDescription.trim()
      ? args.longDescription.trim()
      : null,
    targetAudience: typeof args.targetAudience === "string" && args.targetAudience.trim()
      ? args.targetAudience.trim()
      : null,
    language: typeof args.language === "string" && args.language.trim() ? args.language.trim() : null,
  };
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
  const limit = typeof body.limit === "number" && body.limit > 0 ? Math.min(body.limit, 50) : 20;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Auswahl über references_checked_at statt "hat noch keine
  // event_works/event_participants-Zeile" — ein Event mit ausschließlich
  // unbekannten Mitwirkenden (→ landen als entity_candidates, keine
  // Verknüpfung) bekäme sonst NIE eine solche Zeile und würde bei jedem Lauf
  // erneut ausgewählt, was den gesamten Batch-Fortschritt blockiert (siehe
  // 20260722000001_events_references_checked_at.sql).
  // order by start_datetime statt id: auf Nutzerwunsch priorisieren bevor-
  // stehende Events (insbesondere die nächsten 90 Tage) automatisch zuerst,
  // statt in beliebiger Insert-Reihenfolge verarbeitet zu werden.
  const { data: candidates, error: fetchError } = await supabase
    .from("events")
    .select(
      "id, title, description_de, website_url, ticket_url, doors_info, duration_minutes, has_intermission, target_audience, performance_language",
    )
    .eq("status", "scheduled")
    .is("references_checked_at", null)
    .order("start_datetime", { ascending: true })
    .limit(limit)
    .returns<EventRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!candidates || candidates.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine ungeprüften Events mehr übrig." }));
  }

  let worksCreated = 0;
  let workDuplicatesFlagged = 0;
  let personsFlagged = 0;
  let ensemblesFlagged = 0;
  let linksCreated = 0;
  let genresAssigned = 0;
  const errors: string[] = [];

  for (const event of candidates) {
    // Volltext der offiziellen Seite als zusätzlicher Kontext (siehe
    // Datei-Kommentar zu extractReferences) — website_url zuerst, dann
    // ticket_url. Ohne beide URLs oder bei Fetch-Fehler bleibt pageText
    // null, die Extraktion fällt auf title+description_de zurück wie
    // bisher (kein Fehlerfall).
    let pageText: string | null = null;
    for (const pageUrl of [event.website_url, event.ticket_url]) {
      if (!pageUrl) continue;
      pageText = await fetchPageText(pageUrl);
      if (pageText) break;
    }

    const extracted = await extractReferences(event.title, event.description_de, pageText);
    if (!extracted) {
      errors.push(`"${event.title}": AI-Aufruf fehlgeschlagen (alle Provider)`);
      continue; // kein Mark — bei transientem Providerfehler soll ein späterer Lauf es erneut versuchen
    }

    // Als geprüft markieren, SOBALD die Extraktion selbst geklappt hat —
    // unabhängig davon, ob am Ende Links entstehen (unbekannte Mitwirkende
    // landen nur als entity_candidates) oder ein einzelner DB-Insert weiter
    // unten fehlschlägt. Sonst würde genau dieses Event beim nächsten Lauf
    // wieder ausgewählt und der Batch käme nie über die ersten paar Events
    // hinaus (siehe Migrationskommentar).
    await supabase.from("events").update({ references_checked_at: new Date().toISOString() }).eq("id", event.id);

    // Cache innerhalb dieses Laufs, um nicht pro Event erneut nachzuschlagen,
    // wenn derselbe Name (z. B. ein Hausorchester) mehrfach vorkommt. `null`
    // heißt "unbekannt, bereits als entity_candidate geflaggt" — auch das
    // wird gecacht, um nicht zweimal denselben Kandidaten anzulegen.
    const personCache = new Map<string, string | null>();
    const ensembleCache = new Map<string, string | null>();

    // Unbekannte Namen werden NICHT mehr ungeprüft in persons/ensembles
    // angelegt (das hat früher ohne jede Prüfung neue Stammdaten erzeugt).
    // ABER: wenn die Tavily+LLM-Anreicherung (enrichCandidateContext) mit
    // confident=true eindeutig bestätigt, dass der Name zu einem/einer
    // echten klassischen Musiker*in/Ensemble gehört, UND es keinen
    // ambivalenten possibleMatch (Namensvetter-Risiko) gibt, legt die KI
    // den Stammdaten-Eintrag selbst an, statt ihn liegen zu lassen — das
    // war laut Nutzer-Feedback zu viel manueller Aufwand für eindeutige
    // Fälle. Bleibt trotzdem konservativ: bei jeder Unklarheit (nicht
    // confident, oder ein möglicher Namensvetter bereits bekannt) landet
    // der Kandidat wie bisher als entity_candidates zur redaktionellen
    // Freigabe (siehe 20260818000004_entity_candidates.sql). Rückgabe null
    // heißt "noch keine ID verfügbar" — der Aufrufer verknüpft dann (noch)
    // nichts.
    async function flagEntityCandidate(
      entityType: "person" | "ensemble",
      name: string,
      possibleMatch?: { id: string; name: string; similarity: number },
    ): Promise<string | null> {
      // Platzhalter aus Besetzungslisten ("N.N." für noch unbestimmte
      // Mitwirkende, einzelne Initialen, "TBA"/"TBD") sind keine echten
      // Namen und sollen erst gar nicht als Kandidat landen — vorher
      // musste die Redaktion jeden davon einzeln ablehnen.
      if (isPlaceholderName(name)) return null;

      const { data: existingCandidate } = await supabase
        .from("entity_candidates")
        .select("id")
        .eq("entity_type", entityType)
        .ilike("name", name)
        .eq("status", "pending")
        .maybeSingle();
      if (existingCandidate) return null;

      const enrichment = await enrichCandidateContext(entityType, name);

      if (enrichment && !possibleMatch) {
        const newId = await autoCreateEntity(entityType, name, enrichment);
        if (newId) return newId;
        // Anlegen fehlgeschlagen (z.B. Slug-Kollision, DB-Fehler) — als
        // Fallback trotzdem als Kandidat parken statt den Namen zu verlieren.
      }

      const { error } = await supabase.from("entity_candidates").insert({
        entity_type: entityType,
        name,
        discovery_context: {
          source: "enrich-event-references",
          event_id: event.id,
          ...(enrichment ? { tavily: enrichment } : {}),
          ...(possibleMatch ? { possible_match: possibleMatch } : {}),
        },
        suggested_event_title: event.title,
      });
      if (error) console.error(`flagEntityCandidate "${name}": ${error.message}`);
      return null;
    }

    /** Legt persons/ensembles-Zeile direkt an (is_verified: false — wie bei
     * einer manuellen Redaktions-Freigabe, siehe admin/entity-candidates/
     * actions.ts approveEntityCandidate) und protokolliert das als
     * KI-Entscheidung im Audit-Log. Gibt null zurück statt zu werfen, wenn
     * irgendetwas schiefgeht — der Aufrufer fällt dann auf den normalen
     * Review-Pfad zurück. */
    async function autoCreateEntity(
      entityType: "person" | "ensemble",
      name: string,
      enrichment: { bioSnippet: string | null; websiteUrl: string | null },
    ): Promise<string | null> {
      const slug = await generateUniqueSlug(entityType === "person" ? "persons" : "ensembles", name);
      const table = entityType === "person" ? "persons" : "ensembles";
      const payload =
        entityType === "person"
          ? { full_name: name, slug, is_verified: false, website_url: enrichment.websiteUrl }
          : { name, slug, type: "sonstiges", is_verified: false, website_url: enrichment.websiteUrl };

      const { data, error } = await supabase.from(table).insert(payload).select("id").single();
      if (error || !data) {
        console.error(`autoCreateEntity "${name}" (${entityType}): ${error?.message ?? "kein Ergebnis"}`);
        return null;
      }

      await logSystemAction(supabase, entityType, data.id, "ai_auto_approved", {
        name,
        event_id: event.id,
        bio_snippet: enrichment.bioSnippet,
      }, "system (AI-Entscheidung)");

      // Bisher fehlte hier field_provenance — im Unterschied zum Personen-
      // Merge (siehe resolve-person-duplicates) ist das Anlegen selbst kein
      // Löschvorgang und die Websuche liefert eine zitierbare Quelle, daher
      // bewusst nicht in eine Review-Queue verschoben, sondern nur um die
      // Nachvollziehbarkeit ergänzt — sonst taucht dieser Datensatz in
      // /data-quality nie mit einer Quelle auf.
      if (enrichment.websiteUrl) {
        await recordFieldSource(supabase, {
          entityType,
          entityId: data.id,
          fieldName: "website_url",
          sourceUrl: enrichment.websiteUrl,
          sourceName: "Websuche (enrich-event-references, automatisch angelegt)",
          confidence: "likely",
        });
      }

      return data.id;
    }

    /** Slug-Generierung dupliziert aus ingest-source/write.ts (dort
     * slugify()/generateUniqueSlug()) — kein gemeinsamer Modul-Raum
     * zwischen den einzelnen Edge Functions, siehe dortigen Kommentar. */
    async function generateUniqueSlug(table: "persons" | "ensembles", name: string): Promise<string> {
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
        const { data } = await supabase.from(table).select("id").eq("slug", candidate).maybeSingle();
        if (!data) return candidate;
      }
      return `${base}-${crypto.randomUUID().slice(0, 8)}`;
    }

    // Schwellwerte für Fuzzy-Matching (Architektur-Dokument Abschnitt 2.3):
    // >= AUTO-Schwelle wird automatisch verknüpft (nur geloggt, kein Review
    // nötig — Tippfehler/Kleinschreibungsvarianten sind hier eindeutig).
    // Zwischen FLAG- und AUTO-Schwelle wird NICHT automatisch verknüpft,
    // sondern nur als Hinweis (`possible_match`) an den entity_candidate
    // angehängt — zwei verschiedene Personen desselben/ähnlichen Namens sind
    // real (z.B. mehrere "Michael Schmidt"), das entscheidet ein Redakteur.
    const FUZZY_AUTO_THRESHOLD = 0.85;
    const FUZZY_FLAG_THRESHOLD = 0.5;

    async function getOrCreatePerson(name: string): Promise<string | null> {
      const key = name.toLowerCase();
      if (personCache.has(key)) return personCache.get(key) ?? null;
      const { data: existing } = await supabase
        .from("persons")
        .select("id")
        .ilike("full_name", name)
        .maybeSingle();
      if (existing) {
        personCache.set(key, existing.id);
        return existing.id;
      }

      const { data: fuzzyMatches } = await supabase.rpc("find_matching_person", { p_name: name });
      const bestMatch = fuzzyMatches?.[0] as { id: string; full_name: string; similarity: number } | undefined;
      if (bestMatch && bestMatch.similarity >= FUZZY_AUTO_THRESHOLD) {
        await logSystemAction(supabase, "person", bestMatch.id, "fuzzy_auto_link", {
          matched_name: name,
          linked_to: bestMatch.full_name,
          similarity: bestMatch.similarity,
          event_id: event.id,
        });
        personCache.set(key, bestMatch.id);
        return bestMatch.id;
      }

      const autoCreatedId = await flagEntityCandidate(
        "person",
        name,
        bestMatch && bestMatch.similarity >= FUZZY_FLAG_THRESHOLD
          ? { id: bestMatch.id, name: bestMatch.full_name, similarity: bestMatch.similarity }
          : undefined,
      );
      if (autoCreatedId) {
        personCache.set(key, autoCreatedId);
        return autoCreatedId;
      }
      personsFlagged++;
      personCache.set(key, null);
      return null;
    }

    async function getOrCreateEnsemble(name: string, _type: string | null): Promise<string | null> {
      const key = name.toLowerCase();
      if (ensembleCache.has(key)) return ensembleCache.get(key) ?? null;
      const { data: existing } = await supabase
        .from("ensembles")
        .select("id")
        .ilike("name", name)
        .maybeSingle();
      if (existing) {
        ensembleCache.set(key, existing.id);
        return existing.id;
      }

      const { data: fuzzyMatches } = await supabase.rpc("find_matching_ensemble", { p_name: name });
      const bestMatch = fuzzyMatches?.[0] as { id: string; name: string; similarity: number } | undefined;
      if (bestMatch && bestMatch.similarity >= FUZZY_AUTO_THRESHOLD) {
        await logSystemAction(supabase, "ensemble", bestMatch.id, "fuzzy_auto_link", {
          matched_name: name,
          linked_to: bestMatch.name,
          similarity: bestMatch.similarity,
          event_id: event.id,
        });
        ensembleCache.set(key, bestMatch.id);
        return bestMatch.id;
      }

      const autoCreatedId = await flagEntityCandidate(
        "ensemble",
        name,
        bestMatch && bestMatch.similarity >= FUZZY_FLAG_THRESHOLD
          ? { id: bestMatch.id, name: bestMatch.name, similarity: bestMatch.similarity }
          : undefined,
      );
      if (autoCreatedId) {
        ensembleCache.set(key, autoCreatedId);
        return autoCreatedId;
      }
      ensemblesFlagged++;
      ensembleCache.set(key, null);
      return null;
    }

    // Live beobachtet: dasselbe Werk (Brahms' 4. Sinfonie) wurde DREIFACH
    // angelegt — "4. Sinfonie e-Moll", "4. Sinfonie", "4. Symphonie" — aus
    // zwei unabhängigen Gründen, die beide hier behoben werden:
    //  1) Anführungszeichen-Varianten ("Overture to »A Midsummer Night's
    //     Dream«" vs. ohne »«) — ilike vergleicht exakt (case-insensitive),
    //     keine Sonderzeichen-Normierung.
    //  2) "Sinfonie"/"Symphonie" sind dasselbe Wort auf Deutsch/aus dem
    //     Englischen übernommen, UND die Tonart steht mal im Titel selbst,
    //     mal nur im separaten key_signature-Feld — beides muss beim
    //     Vergleich ignoriert werden, sonst gilt "X e-Moll" nicht als
    //     dasselbe Werk wie "X" (mit key_signature="e-Moll" separat).
    // Der GESPEICHERTE Titel bleibt unverändert wie vom Modell geliefert —
    // nur der Vergleich normalisiert.
    // Bug (live in der App gefunden): "Matthäus-Passion" (mit separatem
    // catalog_number="BWV 244") und "Matthäus-Passion BWV 244" (Katalognummer
    // in den Titel eingebacken, ohne eigenes catalog_number-Feld) wurden als
    // zwei verschiedene Werke angelegt und dadurch im Programm doppelt
    // angezeigt — die Normalisierung strippte zwar einen angehängten
    // Tonart-Suffix, aber keinen angehängten Katalognummer-Suffix. Gleiches
    // CATALOG_PATTERN wie bei der Feld-Vertauschungs-Prüfung weiter oben.
    function normalizeTitleForMatch(title: string): string {
      return title
        .replace(/[»«"""'']/g, "")
        .replace(/symphonie/gi, "sinfonie")
        .replace(/\s+[a-h](-dur|-moll)\s*$/i, "")
        .replace(/\s+(op\.?|opus|bwv|kv|k\.?v\.?|hob\.?|woo|d\.?)\s?\d+[a-z]?\s*$/i, "")
        .replace(/\s+/g, " ")
        .trim()
        .toLowerCase();
    }

    try {
      for (const [i, w] of extracted.works.entries()) {
        if (!w.title?.trim()) continue;
        const composerId = w.composerName?.trim() ? await getOrCreatePerson(w.composerName.trim()) : null;

        const normalizedTitle = normalizeTitleForMatch(w.title);
        // Vorauswahl über einen Teilstring DES NORMALISIERTEN Titels (nicht
        // des rohen) — sonst würde ein führendes »-Zeichen im rohen Titel
        // genau die Fälle verfehlen, die dieser Fix eigentlich abdecken
        // soll (ein bereits ohne Anführungszeichen gespeicherter Titel
        // matcht nicht gegen ein Suchmuster, das noch das » enthält).
        const { data: sameNamedWorks } = await supabase
          .from("works")
          .select("id, title, composer_id, catalog_number, key_signature")
          .ilike("title", `%${normalizedTitle.slice(0, 20)}%`);
        const existingWork = (sameNamedWorks ?? []).find(
          (existing: { title: string }) => normalizeTitleForMatch(existing.title) === normalizedTitle,
        );

        // Kein exakter Treffer nach Normalisierung — Fuzzy-Fallback über
        // pg_trgm (find_similar_works, siehe 20260909000003). Deckt
        // Beinamen-Varianten ab, die normalizeTitleForMatch nicht auflöst
        // (z.B. "Sinfonie Nr. 4 c-moll" vs. "Sinfonie Nr. 4 c-moll
        // 'Tragische'" — live beobachtet im Komponisten-Backfill-Testbatch:
        // ohne dies legt jeder Lauf mit leicht anderem Titel ein neues
        // Duplikat-Werk an). Nur bei hoher Ähnlichkeit UND
        // widerspruchsfreiem Komponisten (einer der beiden fehlt oder
        // beide stimmen überein) automatisch als dasselbe Werk behandeln —
        // sonst lieber anlegen und zur redaktionellen Prüfung vormerken
        // (work_duplicate_candidates), nie blind zusammenlegen.
        let fuzzyMatch:
          | { id: string; title: string; composer_id: string | null; catalog_number: string | null; key_signature: string | null; similarity: number }
          | null = null;
        if (!existingWork) {
          const { data: similarWorks } = await supabase.rpc("find_similar_works", {
            p_title: w.title.trim(),
            p_event_id: event.id,
          });
          fuzzyMatch = (similarWorks ?? [])[0] ?? null;
        }
        // composer_id-Konflikt (beide gesetzt, aber verschieden) ist ein
        // GEGENBEWEIS, kein Unsicherheitsfall — "Symphonie Nr. 1" von
        // Beethoven und "Symphonie Nr. 1" von Brahms sind per Definition
        // unterschiedliche Werke, unabhängig von der Titel-Ähnlichkeit.
        // Live beobachtet: ohne diese Prüfung flutete allein die generische
        // Titel-Vokabular-Überschneidung ("Symphonie Nr. X", "Konzert für
        // ... und Orchester") die Review-Queue mit Dutzenden eindeutig
        // falschen Kandidaten.
        const composerConflict = fuzzyMatch?.composer_id != null && composerId != null &&
          fuzzyMatch.composer_id !== composerId;
        const fuzzyIsSameWork = fuzzyMatch != null && !composerConflict &&
          fuzzyMatch.similarity >= 0.6 &&
          (!fuzzyMatch.composer_id || !composerId || fuzzyMatch.composer_id === composerId);

        let workId: string;
        if (existingWork || fuzzyIsSameWork) {
          const matched = existingWork ?? fuzzyMatch!;
          workId = matched.id;
          // Opus/Tonart/Komponist nur NACHTRÄGLICH ergänzen, wenn das Werk
          // sie noch nicht hat — nie eine bereits vorhandene (ggf.
          // redaktionell gepflegte) Angabe überschreiben. composer_id fehlte
          // hier bisher komplett (nur catalog_number/key_signature wurden
          // je nachgepflegt) — ein erneuter Lauf, der denselben Titel matcht
          // aber diesmal den Komponisten erkennt (z. B. weil fetchPageText
          // jetzt Zeilenstruktur erhält statt zu einem Fließtext-Strom zu
          // verschmelzen), konnte den fehlenden Komponisten dadurch nie
          // nachtragen.
          const patch: Record<string, string> = {};
          if (!matched.composer_id && composerId) patch.composer_id = composerId;
          if (!matched.catalog_number && w.catalogNumber) patch.catalog_number = w.catalogNumber;
          if (!matched.key_signature && w.keySignature) patch.key_signature = w.keySignature;
          if (Object.keys(patch).length > 0) {
            await supabase.from("works").update(patch).eq("id", workId);
          }
        } else {
          const { data: createdWork, error } = await supabase
            .from("works")
            .insert({
              title: w.title.trim(),
              composer_id: composerId,
              catalog_number: w.catalogNumber,
              key_signature: w.keySignature,
            })
            .select("id")
            .single();
          if (error) throw new Error(`works insert "${w.title}": ${error.message}`);
          worksCreated++;
          workId = createdWork.id;

          // Ähnlicher, aber nicht sicher genug für Auto-Match (siehe
          // fuzzyIsSameWork oben) — zur redaktionellen Prüfung vormerken,
          // AUSSER ein Komponisten-Konflikt beweist bereits, dass es
          // unterschiedliche Werke sind (composerConflict oben) — das wäre
          // reines Rauschen in der Review-Queue, kein Zweifelsfall.
          if (fuzzyMatch && !composerConflict) {
            const { error: dupError } = await supabase.from("work_duplicate_candidates").insert({
              work_a_id: fuzzyMatch.id,
              work_b_id: workId,
              similarity_score: fuzzyMatch.similarity,
            });
            if (dupError) errors.push(`work_duplicate_candidates insert "${w.title}": ${dupError.message}`);
            else workDuplicatesFlagged++;
          }
        }
        if (w.catalogNumber || w.keySignature) {
          await recordFieldSource(supabase, {
            entityType: "work",
            entityId: workId,
            fieldName: "catalog_number_key_signature",
            sourceUrl: event.website_url ?? event.ticket_url ?? null,
            sourceName: "Offizielle Veranstaltungsseite (via enrich-event-references)",
            confidence: "likely",
          });
        }

        // PK ist (event_id, work_id, position) — kein simpler (event_id,
        // work_id)-Unique-Constraint, also erst prüfen statt upsert.
        const { data: existingLink } = await supabase
          .from("event_works")
          .select("event_id")
          .eq("event_id", event.id)
          .eq("work_id", workId)
          .maybeSingle();
        if (!existingLink) {
          const { error: linkError } = await supabase
            .from("event_works")
            .insert({ event_id: event.id, work_id: workId, position: i });
          if (linkError) throw new Error(`event_works link: ${linkError.message}`);
          linksCreated++;
        }
      }

      for (const [i, p] of extracted.participants.entries()) {
        if (!p.name?.trim()) continue;
        const isEnsemble = p.type === "ensemble";
        const entityId = isEnsemble
          ? await getOrCreateEnsemble(p.name.trim(), p.ensembleType ?? null)
          : await getOrCreatePerson(p.name.trim());

        // Unbekannter Act — als entity_candidate geflaggt, aber noch keine
        // ID vorhanden. Verknüpfung unterbleibt bis zur Freigabe (siehe
        // getOrCreatePerson/getOrCreateEnsemble oben); kein Fehler.
        if (entityId === null) continue;

        // Existenzprüfung wie bei event_works oben — ohne die legt ein
        // erneuter Lauf für dasselbe Event (z.B. nach einem gezielten
        // references_checked_at-Reset für einen Backfill, siehe
        // 20260829000001_dedupe_event_participants.sql) einen ZWEITEN
        // Eintrag für dieselbe Person/dasselbe Ensemble an — genau das ist
        // hier passiert und zeigte sich als doppelte "Mitwirkende"-Chips
        // in der App.
        const { data: existingParticipant } = await supabase
          .from("event_participants")
          .select("id")
          .eq("event_id", event.id)
          .eq(isEnsemble ? "ensemble_id" : "person_id", entityId)
          .maybeSingle();
        if (existingParticipant) continue;

        const { error: linkError } = await supabase
          .from("event_participants")
          .insert({
            event_id: event.id,
            person_id: isEnsemble ? null : entityId,
            ensemble_id: isEnsemble ? entityId : null,
            role: p.role ?? null,
            display_order: i,
          });
        if (linkError) throw new Error(`event_participants link "${p.name}": ${linkError.message}`);
        linksCreated++;
      }

      for (const tagName of extracted.tags) {
        const trimmed = tagName.trim();
        if (!trimmed) continue;

        const { data: existingTag } = await supabase
          .from("tags")
          .select("id")
          .ilike("name", trimmed)
          .maybeSingle();

        let tagId: string;
        if (existingTag) {
          tagId = existingTag.id;
        } else {
          const { data: createdTag, error: tagInsertError } = await supabase
            .from("tags")
            .insert({ name: trimmed, is_ai_generated: true })
            .select("id")
            .single();
          if (tagInsertError) {
            // Race mit einem parallelen Lauf, der denselben Tag gerade
            // angelegt hat (tags.name ist unique) — kein echter Fehler,
            // einfach überspringen statt den ganzen Event-Write abzubrechen.
            console.error(`tags insert "${trimmed}": ${tagInsertError.message}`);
            continue;
          }
          tagId = createdTag.id;
        }

        const { error: eventTagError } = await supabase
          .from("event_tags")
          .upsert({ event_id: event.id, tag_id: tagId }, { onConflict: "event_id,tag_id" });
        if (eventTagError) console.error(`event_tags link "${trimmed}": ${eventTagError.message}`);
      }

      // genres ist ein kontrolliertes Vokabular (siehe GENRE_SLUGS oben) —
      // im Gegensatz zu tags gibt es nie einen "anlegen"-Zweig, nur
      // Nachschlagen der bereits per Seed-Migration vorhandenen Zeile.
      for (const slug of extracted.genres) {
        const { data: genre } = await supabase.from("genres").select("id").eq("slug", slug).maybeSingle();
        if (!genre) continue; // sollte nicht vorkommen (enum-validiert), sicherheitshalber trotzdem prüfen
        const { error: eventGenreError } = await supabase
          .from("event_genres")
          .upsert({ event_id: event.id, genre_id: genre.id }, { onConflict: "event_id,genre_id" });
        if (eventGenreError) console.error(`event_genres link "${slug}": ${eventGenreError.message}`);
        else genresAssigned++;
      }

      // Praktische Event-Felder — jedes NUR befüllen, wenn aktuell leer,
      // nie eine bereits vorhandene (ggf. redaktionell gepflegte) Angabe
      // überschreiben. longDescription landet in description_de, aber nur
      // wenn dort noch nichts oder nur ein sehr knapper Platzhalter steht
      // (< 40 Zeichen) — die Ingestion setzt description_de oft mit einem
      // kurzen, generischen Quellentext, der durch eine echte redaktionelle
      // Kurzbeschreibung ersetzt werden soll, ohne einen bereits
      // ausführlichen Text zu verlieren.
      const eventPatch: Record<string, string | number | boolean> = {};
      const sourceUrl = event.website_url ?? event.ticket_url ?? undefined;
      const provenanceSources: Array<{ fieldName: string; sourceUrl?: string | null }> = [];

      if (!event.doors_info && extracted.doorsInfo) {
        eventPatch.doors_info = extracted.doorsInfo;
        provenanceSources.push({ fieldName: "doors_info", sourceUrl });
      }
      if (!event.duration_minutes && extracted.estimatedDurationMinutes) {
        eventPatch.duration_minutes = extracted.estimatedDurationMinutes;
        provenanceSources.push({ fieldName: "duration_minutes", sourceUrl });
      }
      // has_intermission hat einen DB-Default von false (nie wirklich
      // NULL) — anders als bei den übrigen Feldern hier IMMER überschreiben,
      // wenn das LLM einen expliziten Wert liefert, statt auf "=== null" zu
      // prüfen (das griff nie, da der Default bereits false ist statt
      // NULL). Vertretbar, weil ein Event durch references_checked_at nur
      // EINMAL durch diese Funktion läuft, nicht wiederkehrend — eine
      // spätere manuelle Redaktions-Korrektur würde also nicht erneut
      // überschrieben.
      if (extracted.hasIntermission !== null) {
        eventPatch.has_intermission = extracted.hasIntermission;
        provenanceSources.push({ fieldName: "has_intermission", sourceUrl });
      }
      if ((!event.description_de || event.description_de.trim().length < 40) && extracted.longDescription) {
        eventPatch.description_de = extracted.longDescription;
        provenanceSources.push({ fieldName: "description_de", sourceUrl });
      }
      if (!event.target_audience && extracted.targetAudience) {
        eventPatch.target_audience = extracted.targetAudience;
        provenanceSources.push({ fieldName: "target_audience", sourceUrl });
      }
      if (!event.performance_language && extracted.language) {
        eventPatch.performance_language = extracted.language;
        provenanceSources.push({ fieldName: "performance_language", sourceUrl });
      }

      if (Object.keys(eventPatch).length > 0) {
        const { error: patchError } = await supabase.from("events").update(eventPatch).eq("id", event.id);
        if (patchError) {
          console.error(`event detail patch "${event.title}": ${patchError.message}`);
        } else {
          await Promise.all(
            provenanceSources.map((s) =>
              recordFieldSource(supabase, {
                entityType: "event",
                entityId: event.id,
                fieldName: s.fieldName,
                sourceUrl: s.sourceUrl,
                sourceName: pageText
                  ? "Offizielle Veranstaltungsseite (via enrich-event-references)"
                  : "Titel/Beschreibung (via enrich-event-references)",
                confidence: pageText ? "likely" : "uncertain",
              })
            ),
          );
        }
      }
    } catch (err) {
      errors.push(`"${event.title}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      processed: candidates.length,
      worksCreated,
      workDuplicatesFlagged,
      personsFlagged,
      ensemblesFlagged,
      linksCreated,
      genresAssigned,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
