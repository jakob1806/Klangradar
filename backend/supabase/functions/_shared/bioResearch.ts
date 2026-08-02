// Recherchiert eine ausführliche deutschsprachige Biografie/Beschreibung für
// eine Person, ein Ensemble oder eine Venue — Nutzeranfrage: "die Künstler
// haben alle zu kurze Bios oder gar keine Bios... entwickle da eine Lösung
// (z.B. einen Scraper), so dass jede Venue, jeder Künstler und jedes
// Ensemble eine Bio hat". Anders als enrichCandidateContext
// (_shared/entityEnrichment.ts, 1-2 Sätze zur bloßen Identifikation eines
// Kandidatennamens) liefert dies einen mehrsätzigen Fließtext, der direkt
// als biography_de/description_de taugt — und ist als reiner Recherche-
// Schritt gedacht, der Text wird NICHT selbst gespeichert (siehe
// research-entity-bio/index.ts), sondern der Redaktion zur Bearbeitung vor
// dem Übernehmen vorgelegt.
//
// Quelle ist die deutsche Wikipedia (_shared/wikipedia.ts), nicht die
// ursprünglich geplante DuckDuckGo-Websuche — live festgestellt, dass
// DuckDuckGos HTML-Endpunkt von Supabase-Edge-IPs aus nur noch eine
// Anti-Bot-Challenge-Seite statt echter Treffer liefert (HTTP 202, 0
// geparste Ergebnisse). Für klassische Musik ist Wikipedia ohnehin oft die
// verlässlichere Quelle.

import { callAiFunction, type AiFunctionDeclaration } from "./ai/router.ts";
import { searchWikipediaExtract } from "./wikipedia.ts";

export type BioEntityType = "person" | "ensemble" | "venue";

/** Bekannte Fakten aus der eigenen Datenbank, gegen die ein Wikipedia-Treffer
 * DETERMINISTISCH geprüft wird — zusätzlich zur (weiterhin bestehenden)
 * LLM-Selbstauskunft ("confident"). Nutzeranfrage: "Verwende Treffer mit
 * mittlerer oder niedriger Konfidenz nicht automatisch" / "berücksichtige...
 * Lebensdaten" — ein Namensvetter-Artikel kann plausiblen Fließtext liefern
 * und trotzdem confident=true von der KI bekommen; ein klar abweichendes
 * Geburts-/Sterbejahr ist ein harter, nicht verhandelbarer Widerspruch. */
export interface KnownFacts {
  birthYear?: number;
  deathYear?: number;
}

const BIRTH_YEAR_PATTERN = /(?:\*|geb\.?|geboren(?:\s+am)?)\s*(?:\d{1,2}\.\s*\w+\s+)?(\d{4})/gi;
const DEATH_YEAR_PATTERN = /(?:†|gest\.?|gestorben(?:\s+am)?)\s*(?:\d{1,2}\.\s*\w+\s+)?(\d{4})/gi;

function extractYears(text: string, pattern: RegExp): number[] {
  return [...text.matchAll(pattern)].map((m) => parseInt(m[1], 10));
}

/** true, wenn der Artikeltext ein Jahr in der erwarteten Rolle (Geburt/Tod)
 * nennt, das dem bekannten Jahr eindeutig widerspricht. Nennt der Text dazu
 * GAR KEIN Jahr (z.B. weil das Extract zu kurz ist), gilt das NICHT als
 * Widerspruch — fehlender Beleg ist etwas anderes als ein Gegenbeleg, hier
 * geht es nur um klare Widersprüche, keine zusätzliche Ablehnungshürde. */
function contradictsKnownYear(text: string, knownYear: number | undefined, pattern: RegExp): boolean {
  if (!knownYear) return false;
  const mentioned = extractYears(text, pattern);
  return mentioned.length > 0 && !mentioned.includes(knownYear);
}

export interface BioResearchResult {
  biography: string;
  sourceUrl: string | null;
  // "wikipedia": aus einem konkreten Artikel zusammengefasst — kann direkt
  // zitiert/verlinkt werden. "ai_knowledge": die KI hat aus ihrem eigenen
  // Trainingswissen geschrieben, ohne eine konkrete Quelle zu belegen —
  // Nutzeranfrage: "es kann doch auch eine KI welche erstellen [wenn kein
  // Wikipedia-Artikel existiert]". Unverifizierter als ein Wikipedia-Fund,
  // die UI weist entsprechend deutlicher auf Prüfbedarf hin.
  source: "wikipedia" | "ai_knowledge";
}

const WRITE_BIOGRAPHY_FUNCTION: AiFunctionDeclaration = {
  name: "write_biography",
  description: "Verfasst eine deutschsprachige Kurzbiografie/-beschreibung aus einem Wikipedia-Artikel.",
  parameters: {
    type: "object",
    properties: {
      biography: {
        type: "string",
        description:
          "3-6 Sätze Fließtext auf Deutsch. Für Personen: musikalischer Werdegang, Instrument/Stimmfach oder " +
          "Schwerpunkt als Komponist:in, bekannte Auszeichnungen/Positionen. Für Ensembles: Gründung, Besetzung/" +
          "Ausrichtung, bekannte Auftritte. Für Venues: Gebäude/Geschichte, Kapazität/Nutzung, Bedeutung für die " +
          "Münchner Konzertszene. Nur Fakten aus dem Artikel, nichts erfinden. Leerer String, wenn der Artikel " +
          "nicht sicher zum gesuchten Namen passt.",
      },
      confident: {
        type: "boolean",
        description:
          "true nur, wenn der Artikel erkennbar zum gesuchten Namen passt (kein Namensvetter, keine andere " +
          "Stadt/Branche/Institution). Sonst false.",
      },
    },
    required: ["confident"],
  },
};

const WRITE_FROM_KNOWLEDGE_FUNCTION: AiFunctionDeclaration = {
  name: "write_biography_from_knowledge",
  description:
    "Verfasst eine deutschsprachige Kurzbiografie/-beschreibung ausschließlich aus eigenem Wissen, ohne Quellenbeleg.",
  parameters: {
    type: "object",
    properties: {
      biography: {
        type: "string",
        description:
          "3-6 Sätze Fließtext auf Deutsch, nur gut belegte, allgemein bekannte Fakten (keine Vermutungen, keine " +
          "erfundenen Details wie genaue Zahlen/Daten, die du nicht sicher weißt). Leerer String, wenn dir zu " +
          "diesem Namen nichts Verlässliches bekannt ist.",
      },
      recognized: {
        type: "boolean",
        description:
          "true nur, wenn du diese konkrete Person/dieses Ensemble/diese Venue (im Kontext klassischer Musik in " +
          "München) tatsächlich kennst. false, wenn dir der Name nichts sagt — dann NICHTS erfinden.",
      },
    },
    required: ["recognized"],
  },
};

const KIND_LABEL: Record<BioEntityType, string> = {
  person: "klassische:r Musiker:in/Komponist:in",
  ensemble: "Ensemble/Orchester/Chor",
  venue: "Konzert-/Veranstaltungsort",
};

async function researchFromKnowledge(
  entityType: BioEntityType,
  name: string,
  context?: string | null,
): Promise<BioResearchResult | null> {
  const kind = KIND_LABEL[entityType];
  const response = await callAiFunction(
    `Du schreibst eine Kurzbiografie/-beschreibung für ${kind} für eine Münchner Konzert-Datenbank, rein aus ` +
      "deinem eigenen Wissen (keine Websuche verfügbar). Sei konservativ: kennst du den Namen nicht sicher oder " +
      "bist du dir bei Details unsicher, recognized=false bzw. lass unsichere Details weg. Erfinde nichts.",
    `Name: "${name}"${context ? `\nZusätzlicher Kontext: ${context}` : ""}`,
    WRITE_FROM_KNOWLEDGE_FUNCTION,
  );
  const args = response?.args;
  if (!args || args.recognized !== true) return null;
  const biography = typeof args.biography === "string" ? args.biography.trim() : "";
  if (!biography) return null;

  return { biography, sourceUrl: null, source: "ai_knowledge" };
}

/** `context` sind zusätzliche bekannte Anhaltspunkte (z.B. Rolle/Instrument
 * bei Personen, Stadtteil bei Venues) — verbessert die Suchtrefferqualität,
 * rein optional. `knownFacts` sind dieselbe Art Anhaltspunkt, aber für einen
 * deterministischen Gegencheck NACH der LLM-Zusage genutzt (siehe
 * contradictsKnownYear oben) — ein Namensvetter-Artikel kann die KI trotzdem
 * überzeugen, ein klar falsches Geburts-/Sterbejahr aber nicht. Versucht
 * zuerst Wikipedia (belegbare Quelle); findet sich dort nichts Verlässliches
 * oder widerspricht der Treffer den bekannten Fakten, schreibt die KI
 * ersatzweise aus eigenem Wissen (researchFromKnowledge) — klar als
 * "ai_knowledge" markiert, damit die Redaktion weiß, dass hier nichts
 * gegengeprüft wurde. Gibt nur dann null zurück, wenn auch das nichts
 * liefert; Aufrufer zeigen das als "keine Recherche möglich" an, nie als
 * technischen Fehler. */
export async function researchBiography(
  entityType: BioEntityType,
  name: string,
  context?: string | null,
  knownFacts?: KnownFacts,
): Promise<BioResearchResult | null> {
  const kind = KIND_LABEL[entityType];
  const hit = await searchWikipediaExtract(context ? `${name} ${context}` : name);

  if (hit?.extract) {
    const response = await callAiFunction(
      `Du fasst einen Wikipedia-Artikel zu einer möglichen ${kind} für eine Münchner Konzert-Datenbank zu einer ` +
        "eigenständig formulierten Kurzbiografie/-beschreibung zusammen. Sei konservativ: passt der Artikel " +
        "erkennbar NICHT zum gesuchten Namen (Namensvetter, komplett andere Person/Institution, falsche Branche), " +
        "confident=false und leere Felder. Erfinde nichts, was nicht im Artikel steht.",
      `Gesuchter Name: "${name}"${context ? `\nZusätzlicher Kontext: ${context}` : ""}\n\n` +
        `Wikipedia-Artikel "${hit.title}":\n${hit.extract}`,
      WRITE_BIOGRAPHY_FUNCTION,
    );
    const args = response?.args;
    const biography = typeof args?.biography === "string" ? args.biography.trim() : "";
    const yearContradiction =
      contradictsKnownYear(hit.extract, knownFacts?.birthYear, BIRTH_YEAR_PATTERN) ||
      contradictsKnownYear(hit.extract, knownFacts?.deathYear, DEATH_YEAR_PATTERN);
    if (args?.confident === true && biography && !yearContradiction) {
      return { biography, sourceUrl: hit.url, source: "wikipedia" };
    }
  }

  return researchFromKnowledge(entityType, name, context);
}
