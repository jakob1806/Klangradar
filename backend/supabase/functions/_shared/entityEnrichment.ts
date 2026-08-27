// Gemeinsamer Baustein: Websuche + LLM-Einordnung für einen vermeintlichen
// klassischen Musiker/ein Ensemble — genutzt sowohl beim erstmaligen Anlegen
// eines entity_candidate (enrich-event-references) als auch beim
// nachträglichen Batch-Review bereits wartender Kandidaten
// (resolve-entity-candidates). confident=true ist die Voraussetzung dafür,
// dass eine KI-Entscheidung den Kandidaten automatisch auflösen darf statt
// ihn liegen zu lassen — siehe beide Aufrufer für die jeweilige Verwendung.
//
// Bug (live entdeckt): nutzte ursprünglich Tavily (_shared/tavily.ts), dessen
// kostenloses Monatskontingent bereits an anderer Stelle in dieser Sitzung
// als ausgeschöpft festgestellt wurde (siehe discover-sources' Umstieg auf
// DuckDuckGo) — searchTavily gab dadurch für JEDEN Kandidaten null zurück,
// wodurch die komplette Warteliste (134 Kandidaten) zwar bei jedem Lauf
// erneut geprüft (ai_last_checked_at gesetzt), aber NIE mehr ein einziger
// automatisch angelegt wurde. Auf denselben kostenlosen DuckDuckGo-Ersatz
// umgestellt: erst Link-Suche, dann Volltext der Top-Treffer statt Tavilys
// fertiger Snippets.
import { callAiFunction, type AiFunctionDeclaration } from "./ai/router.ts";
import { searchDuckDuckGo } from "./duckDuckGoSearch.ts";
import { fetchPageText } from "./pageText.ts";

export interface EntityEnrichment {
  bioSnippet: string | null;
  websiteUrl: string | null;
  resolvedEntityType: "person" | "ensemble";
}

const SUMMARIZE_ARTIST_FUNCTION: AiFunctionDeclaration = {
  name: "summarize_artist",
  description:
    "Fasst Websuche-Treffer zu einem/einer klassischen Musiker*in/Ensemble zu einer kurzen " +
    "Einordnung für die redaktionelle Prüfung zusammen.",
  parameters: {
    type: "object",
    properties: {
      bioSnippet: {
        type: "string",
        description:
          "1-2 Sätze Einordnung (z. B. Instrument/Stimmfach, bekannt für, Orchester-Zugehörigkeit), " +
          "nur wenn die Treffer erkennbar dieselbe Person/dasselbe Ensemble betreffen. Sonst leerer String.",
      },
      websiteUrl: {
        type: "string",
        description: "Offizielle Website/Künstlerprofil-URL, falls unter den Treffern erkennbar, sonst leerer String.",
      },
      confident: {
        type: "boolean",
        description:
          "true nur, wenn die Treffer klar zu einem/einer klassischen Musiker*in/Ensemble mit diesem Namen " +
          "passen. false bei Namensvettern, Unklarheit oder komplett fehlendem Bezug zu klassischer Musik.",
      },
      resolvedEntityType: {
        type: "string",
        enum: ["person", "ensemble", "organization", "venue", "role_or_character", "generic_or_text", "unknown"],
        description:
          "Was der Name laut den Quellen tatsächlich bezeichnet. Institutionen, Opernhäuser, Rundfunkanstalten, " +
          "Agenturen und Veranstalter sind organization – niemals ensemble.",
      },
      exactNameMatch: {
        type: "boolean",
        description: "true nur, wenn die Treffer exakt diese benannte Entität und nicht nur einen ähnlichen Namen behandeln.",
      },
    },
    required: ["confident", "resolvedEntityType", "exactNameMatch"],
  },
};

/** Websuche + LLM-Zusammenfassung für einen Kandidatennamen. Gibt null
 * zurück, wenn die Suche nichts findet, keiner der Treffer Text hergibt,
 * oder das LLM nicht confident=true zurückgibt — Aufrufer behandeln null
 * als "keine verlässliche Anreicherung möglich", nie als Fehler. */
export async function enrichCandidateContext(
  entityType: "person" | "ensemble",
  name: string,
  context?: string | null,
): Promise<EntityEnrichment | null> {
  const kind = entityType === "person" ? "Musiker" : "Ensemble";
  // Kein fest verdrahtetes „München“: Seit BHFW kommen Kandidaten aus mehreren
  // Städten, zudem sind Gastkünstler oft nicht am Veranstaltungsort ansässig.
  // Falls der Import einen Ort/Quellkontext kennt, wird er gezielt ergänzt.
  const contextTerm = context?.trim() ? ` ${context.trim()}` : "";
  const links = await searchDuckDuckGo(`"${name}" ${kind} klassische Musik${contextTerm}`, 3);
  if (!links || links.length === 0) return null;

  const pages = await Promise.all(links.map((l) => fetchPageText(l.url)));
  const searchText = links
    .map((l, i) => (pages[i] ? `${l.url}\n${pages[i]}` : null))
    .filter((t): t is string => t !== null)
    .join("\n\n");
  if (!searchText) return null;
  const response = await callAiFunction(
    "Du klassifizierst Websuche-Treffer zu einem möglichen klassischen Musiker oder Ensemble. " +
      "Sei streng: Ein Opernhaus, Theater, Rundfunksender, Verein, Stiftung, Veranstalter oder eine Agentur ist " +
      "organization und niemals ensemble. Rollen, Figuren, Abteilungen, Gattungswörter und Satzfragmente dürfen " +
      "nicht als Stammdatensatz bestätigt werden. Bei Namensvettern, fehlendem exakten Namensbezug oder Unklarheit " +
      "confident=false setzen. confident=true nur bei exactNameMatch=true und eindeutig passendem Entitätstyp.",
    `Erwarteter Typ: ${entityType}\nGesuchter Name: "${name}"${context ? `\nKontext: ${context}` : ""}\n\nTreffer:\n${searchText}`,
    SUMMARIZE_ARTIST_FUNCTION,
  );
  const args = response?.args;
  if (!args || args.confident !== true || args.exactNameMatch !== true || args.resolvedEntityType !== entityType) return null;

  return {
    bioSnippet: typeof args.bioSnippet === "string" && args.bioSnippet.trim() ? args.bioSnippet.trim() : null,
    websiteUrl: typeof args.websiteUrl === "string" && args.websiteUrl.trim() ? args.websiteUrl.trim() : null,
    resolvedEntityType: entityType,
  };
}
