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
    },
    required: ["confident"],
  },
};

/** Websuche + LLM-Zusammenfassung für einen Kandidatennamen. Gibt null
 * zurück, wenn die Suche nichts findet, keiner der Treffer Text hergibt,
 * oder das LLM nicht confident=true zurückgibt — Aufrufer behandeln null
 * als "keine verlässliche Anreicherung möglich", nie als Fehler. */
export async function enrichCandidateContext(
  entityType: "person" | "ensemble",
  name: string,
): Promise<EntityEnrichment | null> {
  const kind = entityType === "person" ? "Musiker" : "Ensemble";
  // "München" im Suchbegriff — ohne das traf ein generischer Name wie
  // "Markus-Chor" live einen gleichnamigen, aber komplett anderen Chor in
  // Hannover (KI übernahm dessen Website/Leitung/Residenz unkritisch, weil
  // die Suchtreffer selbst schon falsch waren, bevor die LLM-Einordnung
  // überhaupt ansetzt).
  const links = await searchDuckDuckGo(`${name} ${kind} München klassische Musik`, 3);
  if (!links || links.length === 0) return null;

  const pages = await Promise.all(links.map((l) => fetchPageText(l.url)));
  const searchText = links
    .map((l, i) => (pages[i] ? `${l.url}\n${pages[i]}` : null))
    .filter((t): t is string => t !== null)
    .join("\n\n");
  if (!searchText) return null;
  const response = await callAiFunction(
    "Du ordnest Websuche-Treffer zu einem möglichen klassischen Musiker/Ensemble ein. " +
      "Sei konservativ: bei Unklarheit oder Namensvettern lieber confident=false und leere Felder. " +
      "WICHTIG: Der Name stammt aus einer Münchner Konzert-Datenbank — bei generischen Namen " +
      "(z. B. Chor-/Ensemblenamen wie 'Markus-Chor', die es in mehreren Städten geben kann) NUR " +
      "confident=true, wenn die Treffer erkennbar München/Bayern zuordnen. Verweisen Treffer klar " +
      "auf eine andere Stadt (z. B. ein gleichnamiger Chor in Hannover), ist das ein anderer " +
      "Namensvetter — confident=false.",
    `Gesuchter Name: "${name}"\n\nTreffer:\n${searchText}`,
    SUMMARIZE_ARTIST_FUNCTION,
  );
  const args = response?.args;
  if (!args || args.confident !== true) return null;

  return {
    bioSnippet: typeof args.bioSnippet === "string" && args.bioSnippet.trim() ? args.bioSnippet.trim() : null,
    websiteUrl: typeof args.websiteUrl === "string" && args.websiteUrl.trim() ? args.websiteUrl.trim() : null,
  };
}
