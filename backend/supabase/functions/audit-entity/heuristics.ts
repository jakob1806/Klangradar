import { assessEnsembleName } from "../_shared/entityNameValidation.ts";

export type AuditEntityType = "person" | "ensemble" | "venue" | "work" | "event";
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

// Live im Bestand aufgefallen: Ensembles, die nur aus einem Gattungswort
// bestehen ("Chor", "Orchester", …) statt einem konkreten Namen — meist
// aus einer Rollenbezeichnung ("Chor" im Sinne von Chorleitung) statt einer
// echten Ensemble-Nennung fehlgeleitet entstanden.
const GENERIC_ENSEMBLE_NAMES = new Set([
  "chor",
  "chore",
  "orchester",
  "ballett",
  "ensemble",
  "choreographie",
  "choreografie",
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
  // Live im Bestand aufgefallen (Nutzer-Meldung): Ensembles wie "**Chor**",
  // aus nicht bereinigtem Markdown einer Scraping-Quelle übernommen (siehe
  // _shared/staatsoperDetail.ts stripMarkdownEmphasis). Entity-typunabhängig,
  // damit dieselbe Auffälligkeit unabhängig von der Importquelle erkannt wird.
  if (/[*_`]{2,}/.test(trimmed)) {
    issues.push({
      id: "name-markdown-artifact",
      severity: "critical",
      category: "name",
      message: "Der Name enthält Markdown-Formatierungszeichen (z. B. **) statt reinem Text.",
      suggestion: trimmed.replace(/[*_`]{2,}/g, "").trim(),
      source: "rule",
    });
  }
  if (entityType === "ensemble" && GENERIC_ENSEMBLE_NAMES.has(normalized)) {
    issues.push({
      id: "ensemble-generic-name",
      severity: "critical",
      category: "name",
      message: `„${trimmed}“ ist ein bloßes Gattungswort statt eines konkreten Ensemblenamens.`,
      suggestion: "Den offiziellen Ensemblenamen recherchieren (z. B. \"Bayerischer Staatsopernchor\").",
      source: "rule",
    });
  }
  if (entityType === "ensemble") {
    const assessment = assessEnsembleName(trimmed);
    if (!assessment.safe && !GENERIC_ENSEMBLE_NAMES.has(normalized)) {
      issues.push({
        id: "ensemble-wrong-entity-type",
        severity: assessment.reason === "Ticket- oder Informationstext" ? "critical" : "warning",
        category: "contradiction",
        message: `Der Eintrag ist wahrscheinlich kein Ensemble (${assessment.reason ?? "uneindeutig"}).`,
        suggestion: assessment.reason === "sieht wie ein Personenname aus"
          ? "Als Person prüfen und den falschen Ensemble-Eintrag anschließend entfernen."
          : "Nicht als Ensemble übernehmen; Quelle und bestehende Verknüpfungen prüfen.",
        source: "rule",
      });
    }
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

// Tabellen-/Feld-Konfiguration und die Regelprüfung pro Entitätstyp — nach
// heuristics.ts verschoben (statt in index.ts), damit audit-entities-bulk
// (Massenprüfung über alle Personen/Ensembles/Venues/Events) dieselbe Logik
// wiederverwenden kann, ohne index.ts zu importieren (dort läuft
// Deno.serve() auf Modulebene, ein Import würde also einen zweiten
// Server-Handler registrieren).

export const AUDIT_TABLE: Record<AuditEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  venue: "venues",
  work: "works",
  event: "events",
};

export const AUDIT_NAME_FIELD: Record<AuditEntityType, string> = {
  person: "full_name",
  ensemble: "name",
  venue: "name",
  work: "title",
  event: "title",
};

export const AUDIT_ENTITY_SELECT: Record<AuditEntityType, string> = {
  person:
    "id,slug,full_name,first_name,middle_name,last_name,roles,instrument,nationality,birth_date,death_date,website_url,is_verified",
  ensemble:
    "id,slug,name,type,founded_year,member_count,home_venue_id,website_url,is_verified",
  venue:
    "id,slug,name,address_street,address_zip,address_city,capacity,website_url",
  work:
    "id,slug,title,subtitle,composer_id,work_type,catalog_number,duration_minutes,composition_year,description_de",
  event:
    "id,slug,title,subtitle,start_datetime,end_datetime,duration_minutes,venue_id,organizer_id,ticket_url,website_url,price_min,price_max,is_free,status,program_id",
};

export function entitySpecificIssues(
  entityType: AuditEntityType,
  entity: Record<string, unknown>,
): AuditIssue[] {
  const issues: AuditIssue[] = [];
  const add = (issue: Omit<AuditIssue, "source">) =>
    issues.push({ ...issue, source: "rule" });

  if (entityType === "person") {
    const fullName = String(entity.full_name ?? "");
    const firstName = String(entity.first_name ?? "").trim();
    const lastName = String(entity.last_name ?? "").trim();
    if (!firstName || !lastName) {
      add({
        id: "person-name-parts",
        severity: "warning",
        category: "completeness",
        message:
          "Vor- oder Nachname fehlt in den strukturierten Namensfeldern.",
        suggestion:
          "Namensbestandteile anhand des vollständigen offiziellen Namens ergänzen.",
      });
    }
    if (
      lastName &&
      !fullName.toLocaleLowerCase("de").includes(
        lastName.toLocaleLowerCase("de"),
      )
    ) {
      add({
        id: "person-last-name-mismatch",
        severity: "critical",
        category: "contradiction",
        message:
          `Das Feld Nachname „${lastName}“ passt nicht zum vollständigen Namen „${fullName}“.`,
        suggestion: "Namensfelder gemeinsam prüfen und konsistent speichern.",
      });
    }
    const birth = typeof entity.birth_date === "string"
      ? Date.parse(entity.birth_date)
      : Number.NaN;
    const death = typeof entity.death_date === "string"
      ? Date.parse(entity.death_date)
      : Number.NaN;
    if (Number.isFinite(birth) && Number.isFinite(death) && birth > death) {
      add({
        id: "person-date-order",
        severity: "critical",
        category: "contradiction",
        message: "Das Geburtsdatum liegt nach dem Sterbedatum.",
        suggestion:
          "Beide Lebensdaten anhand einer verlässlichen Quelle prüfen.",
      });
    }
  }

  if (entityType === "ensemble") {
    const foundedYear = Number(entity.founded_year);
    const memberCount = Number(entity.member_count);
    const currentYear = new Date().getUTCFullYear();
    if (
      entity.founded_year != null &&
      (!Number.isInteger(foundedYear) || foundedYear < 1000 ||
        foundedYear > currentYear)
    ) {
      add({
        id: "ensemble-founded-year",
        severity: "critical",
        category: "plausibility",
        message: `Das Gründungsjahr „${
          String(entity.founded_year)
        }“ ist unplausibel.`,
        suggestion: "Gründungsjahr anhand der Ensemble-Website prüfen.",
      });
    }
    if (
      entity.member_count != null &&
      (!Number.isInteger(memberCount) || memberCount <= 0 || memberCount > 1000)
    ) {
      add({
        id: "ensemble-member-count",
        severity: "warning",
        category: "plausibility",
        message: `Die Mitgliederzahl „${
          String(entity.member_count)
        }“ ist auffällig.`,
        suggestion:
          "Prüfen, ob die Zahl aktuell ist und tatsächlich Mitglieder statt Mitwirkende eines Einzelprojekts meint.",
      });
    }
  }

  if (entityType === "venue") {
    const zip = String(entity.address_zip ?? "").trim();
    if (!entity.address_street || !zip || !entity.address_city) {
      add({
        id: "venue-address",
        severity: "warning",
        category: "completeness",
        message: "Die Anschrift ist unvollständig.",
        suggestion:
          "Straße, Postleitzahl und Ort anhand der offiziellen Venue-Seite prüfen.",
      });
    }
    if (zip && !/^\d{5}$/.test(zip)) {
      add({
        id: "venue-zip",
        severity: "warning",
        category: "plausibility",
        message:
          `Die Postleitzahl „${zip}“ entspricht nicht dem fünfstelligen deutschen Format.`,
        suggestion: "Postleitzahl und Landeskontext prüfen.",
      });
    }
    const capacity = Number(entity.capacity);
    if (
      entity.capacity != null &&
      (!Number.isInteger(capacity) || capacity <= 0 || capacity > 100_000)
    ) {
      add({
        id: "venue-capacity",
        severity: "warning",
        category: "plausibility",
        message: `Die Kapazität „${String(entity.capacity)}“ ist auffällig.`,
        suggestion: "Sitz-/Stehplatzkapazität und Raumbezug prüfen.",
      });
    }
  }

  if (entityType === "event") {
    const priceMin = entity.price_min == null ? null : Number(entity.price_min);
    const priceMax = entity.price_max == null ? null : Number(entity.price_max);
    if (
      entity.is_free === true && ((priceMin ?? 0) > 0 || (priceMax ?? 0) > 0)
    ) {
      add({
        id: "event-free-price",
        severity: "critical",
        category: "contradiction",
        message:
          "Die Veranstaltung ist als kostenlos markiert, enthält aber gleichzeitig einen positiven Preis.",
        suggestion: "Kostenlos-Markierung oder Preisfelder korrigieren.",
      });
    }
    if (priceMin != null && priceMax != null && priceMin > priceMax) {
      add({
        id: "event-price-order",
        severity: "critical",
        category: "contradiction",
        message: "Der Mindestpreis liegt über dem Höchstpreis.",
        suggestion: "Preisbereich anhand der Ticketseite prüfen.",
      });
    }
    const duration = Number(entity.duration_minutes);
    if (
      entity.duration_minutes != null &&
      (!Number.isFinite(duration) || duration <= 0 || duration > 600)
    ) {
      add({
        id: "event-duration",
        severity: "warning",
        category: "plausibility",
        message: `Die Dauer von „${
          String(entity.duration_minutes)
        }“ Minuten ist auffällig.`,
        suggestion: "Einheit und tatsächliche Gesamtdauer prüfen.",
      });
    }
    if (!entity.venue_id) {
      add({
        id: "event-venue",
        severity: "warning",
        category: "completeness",
        message: "Der Veranstaltung ist keine Venue zugeordnet.",
        suggestion:
          "Spielstätte oder ausdrücklich einen noch unbekannten Ort hinterlegen.",
      });
    }
  }
  return issues;
}
