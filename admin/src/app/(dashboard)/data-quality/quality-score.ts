// Abschnitt 8 der Gesamtüberarbeitung: ein erklärbares Qualitätsmodell statt
// der bisherigen reinen "X von Y Feldern fehlen"-Zählung. Kritische Felder
// zählen stärker, Unsicherheit (fehlende Quelle, offenes Bild-Review, nicht
// aufgelöstes Duplikat-Match) wird als eigenes Signal sichtbar statt in
// einer einzigen Zahl zu verschwinden.
//
// Bewusst NICHT enthalten: ein "Konsistenz"-Teilscore (Abschnitt 8 nennt
// "widersprüchliche Programminfos" als Signal) — dafür gibt es aktuell
// keine tatsächliche Datengrundlage (keine Tabelle/kein Flag, das eine
// erkannte Quellen-Widerspruch festhält). Ihn hier zu erfinden würde gegen
// die eigene Vorgabe verstoßen, nur auf vorhandenen Daten aufzubauen statt
// zu raten — bleibt als offener Punkt für Abschnitt 4 markiert.

export type QualityConfidence = "confirmed" | "likely" | "uncertain" | "unknown";

const CONFIDENCE_SCORE: Record<QualityConfidence, number> = {
  confirmed: 1,
  likely: 0.7,
  uncertain: 0.35,
  unknown: 0.15,
};

/** Ein Teilscore: 0-1 plus der Grund, warum er so ausfällt (Abschnitt 8:
 * "pro Teilscore erklärbar bleiben"). `null` heißt: für diesen Entitätstyp
 * (noch) nicht anwendbar — das Gewicht wird dann unter den übrigen
 * Teilscores neu verteilt statt die Entität dafür zu bestrafen. */
export interface QualitySubScore {
  score: number;
  reason: string;
}

export interface QualityFieldInput {
  /** Anzahl kritischer Felder, die befüllt sind, von `criticalTotal`. */
  criticalPresent: number;
  criticalTotal: number;
  /** Anzahl optionaler Felder, die befüllt sind, von `optionalTotal`. */
  optionalPresent: number;
  optionalTotal: number;
}

export interface QualityScoreInput {
  fields: QualityFieldInput;
  /** Konfidenz-Werte aller field_provenance-Einträge dieser Entität. */
  provenanceConfidences: QualityConfidence[];
  profileCheckedAt: string | null;
  /** null, wenn dieser Entitätstyp keine eigenen Bilder trägt (aktuell:
   * works) — Gewicht wird dann neu verteilt statt mit 0 bestraft. */
  images: { hasNonRejectedImage: boolean; anyNeedsReview: boolean; anyLicenseConfirmed: boolean } | null;
  /** null, solange es für diesen Entitätstyp noch keine Dedup-Review-Queue
   * gibt (Abschnitt E: aktuell nur Personen/Werke, Venues/Ensembles offen). */
  hasPendingDuplicateCandidate: boolean | null;
  now?: Date;
}

export interface QualityBreakdown {
  completeness: QualitySubScore;
  sourceQuality: QualitySubScore;
  recency: QualitySubScore;
  imageCoverage: QualitySubScore | null;
  matchCertainty: QualitySubScore | null;
  /** 0-100, gewichteter Durchschnitt der anwendbaren Teilscores. */
  totalScore: number;
  /** Abschnitt 8: "Unsicherheit sichtbar machen" — unabhängig vom
   * Gesamtscore, damit ein hoher Score offene Prüf-Punkte nicht verdeckt. */
  hasOpenReviewItems: boolean;
  openReviewReasons: string[];
}

const WEIGHTS = {
  completeness: 0.4,
  sourceQuality: 0.2,
  recency: 0.15,
  imageCoverage: 0.15,
  matchCertainty: 0.1,
} as const;

const RECENCY_FRESH_DAYS = 30;
const RECENCY_STALE_DAYS = 365;

function scoreCompleteness(fields: QualityFieldInput): QualitySubScore {
  const criticalWeight = 2;
  const optionalWeight = 1;
  const totalWeight = fields.criticalTotal * criticalWeight + fields.optionalTotal * optionalWeight;
  if (totalWeight === 0) {
    return { score: 1, reason: "Keine Felder definiert" };
  }
  const presentWeight = fields.criticalPresent * criticalWeight + fields.optionalPresent * optionalWeight;
  const missingCritical = fields.criticalTotal - fields.criticalPresent;
  return {
    score: presentWeight / totalWeight,
    reason:
      missingCritical > 0
        ? `${missingCritical} von ${fields.criticalTotal} kritischen Feldern fehlen`
        : `Alle kritischen Felder vorhanden, ${fields.optionalTotal - fields.optionalPresent} optionale fehlen`,
  };
}

function scoreSourceQuality(confidences: QualityConfidence[]): QualitySubScore {
  if (confidences.length === 0) {
    return { score: 0, reason: "Keine Quelle hinterlegt (field_provenance leer)" };
  }
  const avg = confidences.reduce((sum, c) => sum + CONFIDENCE_SCORE[c], 0) / confidences.length;
  return {
    score: avg,
    reason: `${confidences.length} Quelle(n), Konfidenz: ${[...new Set(confidences)].join(", ")}`,
  };
}

function scoreRecency(profileCheckedAt: string | null, now: Date): QualitySubScore {
  if (!profileCheckedAt) {
    return { score: 0, reason: "Nie geprüft (profile_checked_at leer)" };
  }
  const ageDays = (now.getTime() - new Date(profileCheckedAt).getTime()) / (1000 * 60 * 60 * 24);
  if (ageDays <= RECENCY_FRESH_DAYS) {
    return { score: 1, reason: `Vor ${Math.max(0, Math.round(ageDays))} Tagen geprüft` };
  }
  if (ageDays >= RECENCY_STALE_DAYS) {
    return { score: 0, reason: `Vor ${Math.round(ageDays)} Tagen geprüft — gilt als veraltet` };
  }
  const decayed = 1 - (ageDays - RECENCY_FRESH_DAYS) / (RECENCY_STALE_DAYS - RECENCY_FRESH_DAYS);
  return { score: decayed, reason: `Vor ${Math.round(ageDays)} Tagen geprüft` };
}

function scoreImageCoverage(images: QualityScoreInput["images"]): QualitySubScore | null {
  if (images === null) return null;
  if (!images.hasNonRejectedImage) {
    return { score: 0, reason: "Kein verwendbares Bild vorhanden" };
  }
  let score = images.anyLicenseConfirmed ? 1 : 0.5;
  let reason = images.anyLicenseConfirmed ? "Bild mit bestätigter Lizenz vorhanden" : "Bild vorhanden, Lizenz ungeklärt";
  if (images.anyNeedsReview) {
    score = Math.min(score, 0.5);
    reason += ", redaktionelle Prüfung offen";
  }
  return { score, reason };
}

function scoreMatchCertainty(hasPending: boolean | null): QualitySubScore | null {
  if (hasPending === null) return null;
  if (hasPending) {
    return { score: 0.3, reason: "Ungeklärtes mögliches Duplikat in der Review-Queue" };
  }
  return { score: 1, reason: "Kein offenes Duplikat-Match" };
}

/** Reines Berechnungsmodell ohne DB-Zugriff — testbar ohne Supabase-Mock,
 * siehe quality-score.test.ts. Aufrufer (completeness.ts) liefert bereits
 * aggregierte Zahlen/Flags statt roher Zeilen. */
export function computeQualityScore(input: QualityScoreInput): QualityBreakdown {
  const now = input.now ?? new Date();
  const completeness = scoreCompleteness(input.fields);
  const sourceQuality = scoreSourceQuality(input.provenanceConfidences);
  const recency = scoreRecency(input.profileCheckedAt, now);
  const imageCoverage = scoreImageCoverage(input.images);
  const matchCertainty = scoreMatchCertainty(input.hasPendingDuplicateCandidate);

  const applicable: Array<[QualitySubScore, number]> = [
    [completeness, WEIGHTS.completeness],
    [sourceQuality, WEIGHTS.sourceQuality],
    [recency, WEIGHTS.recency],
  ];
  if (imageCoverage) applicable.push([imageCoverage, WEIGHTS.imageCoverage]);
  if (matchCertainty) applicable.push([matchCertainty, WEIGHTS.matchCertainty]);
  const totalWeight = applicable.reduce((sum, [, w]) => sum + w, 0);
  const weightedSum = applicable.reduce((sum, [s, w]) => sum + s.score * w, 0);
  const totalScore = totalWeight > 0 ? Math.round((weightedSum / totalWeight) * 100) : 0;

  const openReviewReasons: string[] = [];
  if (!input.profileCheckedAt) openReviewReasons.push("Noch nie geprüft");
  if (input.images?.anyNeedsReview) openReviewReasons.push("Bild-Review offen");
  if (input.hasPendingDuplicateCandidate) openReviewReasons.push("Mögliches Duplikat offen");
  if (input.provenanceConfidences.some((c) => c === "uncertain" || c === "unknown")) {
    openReviewReasons.push("Unsichere Quelle vorhanden");
  }

  return {
    completeness,
    sourceQuality,
    recency,
    imageCoverage,
    matchCertainty,
    totalScore,
    hasOpenReviewItems: openReviewReasons.length > 0,
    openReviewReasons,
  };
}
