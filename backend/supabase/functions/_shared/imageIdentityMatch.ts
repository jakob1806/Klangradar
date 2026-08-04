// Strukturierte, erklärbare Bild-Identitäts-Prüfung — bisher bekam jeder
// Bildkandidat nur einen pro Quellen-Stufe HARTKODIERTEN Konfidenzwert
// (0.96 eigene Website, 0.86 Wikipedia, 0.82 Wikidata, 0.78 Bild nahe
// Namen, 0.72 Commons-Volltextsuche — siehe enrich-entity-images/index.ts),
// nie aus tatsächlichen Signalen (Name, Rolle/Instrument, Lebensdaten,
// Ensemble, Ort) berechnet. Direkte Vorlage: resolve-person-duplicates'
// MERGE_CHECK_FUNCTION (KI-Function-Call mit reasoning, landet immer in
// einer Review-Queue, nie automatisch ausgeführt) — hier dieselbe
// Disziplin für Bild-zu-Entität-Zuordnungen statt Personen-Duplikate.
//
// Ergebnis fließt NICHT in neue Tabellenspalten (die kämen erst mit einer
// eigenen, noch nicht angewendeten Migration) — matchScore ersetzt den
// bisherigen hartkodierten confidenceScore direkt (gleiche Spalte,
// confidence_score), decisionReason ersetzt/ergänzt match_reason, Konflikte
// werden als zusätzliche warnings-Einträge angehängt. Voll nutzbar mit dem
// heutigen Schema, keine Abhängigkeit von der geplanten Schema-Erweiterung.

import { callAiFunction, type AiFunctionDeclaration } from "./ai/router.ts";

export interface ImageIdentitySignals {
  entityName: string;
  entityKind: "venue" | "person" | "ensemble" | "festival";
  /** Rolle/Instrument bei Personen, z.B. "Dirigent", "Violine". */
  role?: string | null;
  birthDate?: string | null;
  deathDate?: string | null;
  ensemble?: string | null;
  location?: string | null;
  /** Domain der Entität selbst (website_url), zum Abgleich gegen die
   * Quell-Domain des Kandidaten. */
  officialDomain?: string | null;
  /** Domain, von der der Bildkandidat stammt. */
  sourceDomain?: string | null;
  /** Bildunterschrift/Alt-Text/umgebender Text der Quellseite, falls
   * bekannt (z.B. von detectEventCoverImage/coverImageDetection.ts, einem
   * Wikipedia-Extract oder einem Commons-Suchtreffer-Titel). */
  sourceContext?: string | null;
}

export interface ImageIdentityMatchResult {
  matchScore: number;
  subScores: {
    nameMatch: number;
    roleMatch: number;
    dateConsistency: number;
    locationConsistency: number;
    sourceContextMatch: number;
  };
  conflicts: string[];
  decisionReason: string;
}

const IMAGE_MATCH_FUNCTION: AiFunctionDeclaration = {
  name: "assess_image_identity_match",
  description:
    "Bewertet, wie sicher ein Bildkandidat tatsächlich die genannte Person/das Ensemble/die Venue/das Festival " +
    "zeigt — basierend auf Name, Rolle, Lebensdaten, Ensemble, Ort und Quellenkontext, nicht nur dem Namen allein.",
  parameters: {
    type: "object",
    properties: {
      matchScore: {
        type: "number",
        description:
          "Gesamtscore 0-1 für die Identitäts-Sicherheit. 1 = eindeutig dieselbe Entität, 0 = eindeutig eine " +
          "andere. Sei konservativ bei Namensvettern (z.B. gleicher Nachname, andere Person) oder fehlendem Kontext.",
      },
      nameMatch: {
        type: "number",
        description: "0-1: passt der Name (inkl. plausibler Schreibvarianten) zum Kandidaten?",
      },
      roleMatch: {
        type: "number",
        description: "0-1: passt Rolle/Instrument/Funktion, falls im Quellenkontext erkennbar? 0.5 wenn unbekannt.",
      },
      dateConsistency: {
        type: "number",
        description:
          "0-1: sind Lebensdaten (falls im Quellenkontext genannt) konsistent mit den bekannten Daten der " +
          "Entität? 0.5 wenn keine Daten im Kontext genannt werden (kein Widerspruch feststellbar).",
      },
      locationConsistency: {
        type: "number",
        description: "0-1: passt Ort/Ensemble-Zugehörigkeit, falls erkennbar? 0.5 wenn unbekannt.",
      },
      sourceContextMatch: {
        type: "number",
        description: "0-1: bestätigt der umgebende Text/die Bildunterschrift der Quelle die Zuordnung?",
      },
      conflicts: {
        type: "array",
        items: { type: "string" },
        description:
          "Konkrete Widersprüche auf Deutsch, z.B. 'Bildunterschrift nennt ein anderes Sterbejahr' oder " +
          "'Ort passt nicht zur bekannten Wirkungsstätte'. Leeres Array, wenn nichts widerspricht.",
      },
      decisionReason: {
        type: "string",
        description: "Ein bis zwei Sätze auf Deutsch, die den matchScore für die redaktionelle Prüfung begründen.",
      },
    },
    required: ["matchScore", "nameMatch", "roleMatch", "dateConsistency", "locationConsistency", "sourceContextMatch", "conflicts", "decisionReason"],
  },
};

/** Liefert null bei jedem Fehlschlag (kein AI-Provider verfügbar, Timeout,
 * ungültige Antwort) — Aufrufer behandeln das wie "keine automatisierte
 * Einschätzung möglich", fallen auf den bisherigen Tier-Literal als reine
 * Vorab-Schwelle zurück und markieren den Kandidaten sicherheitshalber zur
 * Prüfung, nie als Fehler. */
export async function assessImageIdentityMatch(
  signals: ImageIdentitySignals,
): Promise<ImageIdentityMatchResult | null> {
  const kindLabel = { venue: "Konzert-/Veranstaltungsort", person: "Person", ensemble: "Ensemble/Orchester/Chor", festival: "Festival" }[
    signals.entityKind
  ];

  const contextLines = [
    `Gesuchte Entität: "${signals.entityName}" (${kindLabel})`,
    signals.role ? `Rolle/Instrument: ${signals.role}` : null,
    signals.birthDate || signals.deathDate
      ? `Bekannte Lebensdaten: ${signals.birthDate ?? "?"} – ${signals.deathDate ?? "?"}`
      : null,
    signals.ensemble ? `Bekannte Ensemble-Zugehörigkeit: ${signals.ensemble}` : null,
    signals.location ? `Bekannter Ort: ${signals.location}` : null,
    signals.officialDomain ? `Eigene offizielle Domain: ${signals.officialDomain}` : null,
    signals.sourceDomain ? `Domain des Bildkandidaten: ${signals.sourceDomain}` : null,
    signals.sourceContext ? `Kontext/Bildunterschrift der Quelle:\n${signals.sourceContext}` : "Kein Quellenkontext verfügbar.",
  ].filter((l): l is string => l !== null).join("\n");

  const response = await callAiFunction(
    "Du bewertest, ob ein gefundener Bildkandidat tatsächlich die genannte Person/das Ensemble/die Venue/das " +
      "Festival zeigt, für eine Münchner Klassik-Konzert-Datenbank. Sei konservativ: bei Namensvettern, " +
      "widersprüchlichem Kontext oder fehlenden Anhaltspunkten niedrigere Scores und Konflikte auflisten statt " +
      "zu raten. Ein hoher Score darf nur vergeben werden, wenn mehrere Signale übereinstimmen, nicht allein der Name.",
    contextLines,
    IMAGE_MATCH_FUNCTION,
  );
  const args = response?.args;
  if (
    !args ||
    typeof args.matchScore !== "number" ||
    typeof args.decisionReason !== "string"
  ) return null;

  return {
    matchScore: Math.max(0, Math.min(1, args.matchScore)),
    subScores: {
      nameMatch: typeof args.nameMatch === "number" ? args.nameMatch : 0.5,
      roleMatch: typeof args.roleMatch === "number" ? args.roleMatch : 0.5,
      dateConsistency: typeof args.dateConsistency === "number" ? args.dateConsistency : 0.5,
      locationConsistency: typeof args.locationConsistency === "number" ? args.locationConsistency : 0.5,
      sourceContextMatch: typeof args.sourceContextMatch === "number" ? args.sourceContextMatch : 0.5,
    },
    conflicts: Array.isArray(args.conflicts) ? args.conflicts.filter((c): c is string => typeof c === "string") : [],
    decisionReason: args.decisionReason,
  };
}

export type MatchClassification = "approved" | "pending_review" | "rejected";

/** Zentrale, testbare Schwellenwert-Logik — Konflikte erzwingen IMMER
 * pending_review, unabhängig vom Score (nie ein "guter Score trotz
 * bekanntem Widerspruch" automatisch durchwinken). Schwellenwerte hier
 * konstant statt in einer Konfigurationstabelle (wie z.B.
 * home_feed_ranking_weights) — das wäre ein sinnvoller nächster Schritt,
 * aber ein eigener, separat zu entscheidender Schritt. */
export const AUTO_APPROVE_THRESHOLD = 0.9;
export const REJECT_THRESHOLD = 0.35;

export function classifyMatch(
  matchScore: number,
  conflicts: string[],
): MatchClassification {
  if (conflicts.length > 0) return "pending_review";
  if (matchScore >= AUTO_APPROVE_THRESHOLD) return "approved";
  if (matchScore < REJECT_THRESHOLD) return "rejected";
  return "pending_review";
}
