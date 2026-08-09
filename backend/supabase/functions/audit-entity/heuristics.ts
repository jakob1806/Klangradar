export type AuditEntityType = "person" | "ensemble" | "venue" | "event";
export type AuditSeverity = "critical" | "warning" | "info";

export interface AuditIssue {
  id: string;
  severity: AuditSeverity;
  category:
    | "duplicate"
    | "name"
    | "spelling"
    | "completeness"
    | "contradiction"
    | "plausibility";
  message: string;
  suggestion?: string | null;
  relatedId?: string | null;
  relatedName?: string | null;
  confidence?: number | null;
  source: "rule" | "ai";
}

export interface NameCandidate {
  id: string;
  name: string;
  context?: string | null;
}

export interface ScoredNameCandidate extends NameCandidate {
  score: number;
  reason: string;
}

const PLACEHOLDER_NAMES = new Set([
  "unbekannt",
  "unknown",
  "n n",
  "nn",
  "tba",
  "tbd",
  "diverse",
  "verschiedene",
  "noch offen",
]);

export function normalizeName(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/&/g, " und ")
    .toLocaleLowerCase("de")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function levenshteinDistance(left: string, right: string): number {
  if (!left.length) return right.length;
  if (!right.length) return left.length;
  const previous = Array.from(
    { length: right.length + 1 },
    (_, index) => index,
  );
  for (let i = 1; i <= left.length; i++) {
    let diagonal = previous[0];
    previous[0] = i;
    for (let j = 1; j <= right.length; j++) {
      const above = previous[j];
      previous[j] = left[i - 1] === right[j - 1]
        ? diagonal
        : Math.min(diagonal, above, previous[j - 1]) + 1;
      diagonal = above;
    }
  }
  return previous[right.length];
}

export function nameSimilarity(left: string, right: string): number {
  const a = normalizeName(left);
  const b = normalizeName(right);
  if (!a || !b) return 0;
  if (a === b) return 1;
  const editScore = 1 -
    levenshteinDistance(a, b) / Math.max(a.length, b.length);
  const aTokens = new Set(a.split(" "));
  const bTokens = new Set(b.split(" "));
  const shared = [...aTokens].filter((token) => bTokens.has(token)).length;
  const containment = shared /
    Math.max(1, Math.min(aTokens.size, bTokens.size));
  return Math.max(editScore, containment * 0.92);
}

export function findNameCandidates(
  currentId: string,
  name: string,
  candidates: NameCandidate[],
  limit = 6,
): ScoredNameCandidate[] {
  const normalized = normalizeName(name);
  const currentTokens = normalized.split(" ").filter(Boolean);
  return candidates
    .filter((candidate) => candidate.id !== currentId && candidate.name.trim())
    .flatMap((candidate): ScoredNameCandidate[] => {
      const candidateNormalized = normalizeName(candidate.name);
      const score = nameSimilarity(name, candidate.name);
      const candidateTokens = candidateNormalized.split(" ").filter(Boolean);
      const surnameContainment = currentTokens.length === 1 &&
        candidateTokens.at(-1) === currentTokens[0];
      const reverseSurnameContainment = candidateTokens.length === 1 &&
        currentTokens.at(-1) === candidateTokens[0];
      if (candidateNormalized === normalized) {
        return [{
          ...candidate,
          score: 1,
          reason: "gleiche normalisierte Schreibweise",
        }];
      }
      if (surnameContainment || reverseSurnameContainment) {
        return [{
          ...candidate,
          score: Math.max(score, 0.9),
          reason: "möglicherweise nur Nachname bzw. verkürzter Name",
        }];
      }
      if (score >= 0.78) {
        return [{ ...candidate, score, reason: "sehr ähnliche Schreibweise" }];
      }
      return [];
    })
    .sort((left, right) => right.score - left.score)
    .slice(0, limit);
}

export function basicNameIssues(
  entityType: AuditEntityType,
  rawName: string,
): AuditIssue[] {
  const issues: AuditIssue[] = [];
  const trimmed = rawName.trim();
  const normalized = normalizeName(rawName);
  if (!trimmed) {
    return [{
      id: "name-empty",
      severity: "critical",
      category: "name",
      message: "Der Name ist leer.",
      suggestion: "Einen eindeutigen redaktionellen Namen eintragen.",
      source: "rule",
    }];
  }
  if (rawName !== trimmed || /\s{2,}/.test(rawName)) {
    issues.push({
      id: "name-whitespace",
      severity: "warning",
      category: "name",
      message:
        "Der Name enthält führende, nachgestellte oder doppelte Leerzeichen.",
      suggestion: trimmed.replace(/\s+/g, " "),
      source: "rule",
    });
  }
  if (PLACEHOLDER_NAMES.has(normalized)) {
    issues.push({
      id: "name-placeholder",
      severity: "critical",
      category: "name",
      message:
        `„${trimmed}“ wirkt wie ein Platzhalter statt eines echten Namens.`,
      suggestion:
        "Den offiziellen Namen recherchieren oder den Eintrag bis dahin nicht veröffentlichen.",
      source: "rule",
    });
  }
  if (entityType === "person") {
    const tokens = trimmed.split(/\s+/).filter(Boolean);
    if (tokens.length === 1) {
      issues.push({
        id: "person-single-name",
        severity: "warning",
        category: "completeness",
        message:
          "Die Person ist nur mit einem einzelnen Namen erfasst; möglicherweise fehlt der Vor- oder Nachname.",
        suggestion:
          "Vollständigen Künstlernamen anhand einer offiziellen Quelle prüfen.",
        source: "rule",
      });
    }
    if (/^(?:[A-ZÄÖÜ]\.?\s*){1,3}[A-Za-zÄÖÜäöüß-]+$/.test(trimmed)) {
      issues.push({
        id: "person-initials",
        severity: "info",
        category: "completeness",
        message: "Der Vorname scheint nur als Initiale erfasst zu sein.",
        suggestion: "Prüfen, ob der ausgeschriebene Vorname verfügbar ist.",
        source: "rule",
      });
    }
  }
  if (/^[a-zäöüß]/.test(trimmed)) {
    issues.push({
      id: "name-lowercase",
      severity: "warning",
      category: "spelling",
      message: "Der Name beginnt ungewöhnlich mit einem Kleinbuchstaben.",
      suggestion:
        "Groß-/Kleinschreibung anhand der offiziellen Eigenschreibweise prüfen.",
      source: "rule",
    });
  }
  if (/([!?.,;:])\1{1,}/.test(trimmed) || /["“”'‘’]{2,}/.test(trimmed)) {
    issues.push({
      id: "name-punctuation",
      severity: "warning",
      category: "spelling",
      message:
        "Der Name enthält auffällige doppelte Satz- oder Anführungszeichen.",
      suggestion: "Zeichensetzung und offizielle Schreibweise prüfen.",
      source: "rule",
    });
  }
  return issues;
}

export function duplicateIssues(
  candidates: ScoredNameCandidate[],
): AuditIssue[] {
  return candidates.map((candidate, index) => ({
    id: `duplicate-${candidate.id}-${index}`,
    severity: candidate.score >= 0.98 ? "critical" : "warning",
    category: "duplicate",
    message:
      `Möglicher doppelter oder abweichend geschriebener Eintrag: „${candidate.name}“ (${
        Math.round(candidate.score * 100)
      } % Namensähnlichkeit).`,
    suggestion: `Einträge vergleichen; Signal: ${candidate.reason}.`,
    relatedId: candidate.id,
    relatedName: candidate.name,
    confidence: candidate.score,
    source: "rule",
  }));
}

export function deduplicateIssues(issues: AuditIssue[]): AuditIssue[] {
  const seen = new Set<string>();
  return issues.filter((issue) => {
    const key = `${issue.category}:${issue.relatedId ?? ""}:${
      normalizeName(issue.message)
    }`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
