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

export interface BioResearchResult {
  biography: string;
  sourceUrl: string | null;
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

const KIND_LABEL: Record<BioEntityType, string> = {
  person: "klassische:r Musiker:in/Komponist:in",
  ensemble: "Ensemble/Orchester/Chor",
  venue: "Konzert-/Veranstaltungsort",
};

/** `context` sind zusätzliche bekannte Anhaltspunkte (z.B. Rolle/Instrument
 * bei Personen, Stadtteil bei Venues) — verbessert die Suchtrefferqualität,
 * rein optional. Gibt null zurück, wenn die Suche nichts Verlässliches
 * findet; Aufrufer zeigen das als "keine Recherche möglich" an, nie als
 * technischen Fehler. */
export async function researchBiography(
  entityType: BioEntityType,
  name: string,
  context?: string | null,
): Promise<BioResearchResult | null> {
  const kind = KIND_LABEL[entityType];
  const hit = await searchWikipediaExtract(context ? `${name} ${context}` : name);
  if (!hit || !hit.extract) return null;

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
  if (!args || args.confident !== true) return null;
  const biography = typeof args.biography === "string" ? args.biography.trim() : "";
  if (!biography) return null;

  return {
    biography,
    sourceUrl: hit.url,
  };
}
