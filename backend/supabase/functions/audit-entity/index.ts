import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  type AiFunctionDeclaration,
  callAiFunction,
  hasAnyAiProviderConfigured,
} from "../_shared/ai/router.ts";
import {
  type AuditEntityType,
  type AuditIssue,
  basicNameIssues,
  deduplicateIssues,
  duplicateIssues,
  findNameCandidates,
  type NameCandidate,
  nameSimilarity,
} from "./heuristics.ts";

type JsonRecord = Record<string, unknown>;

const TABLE: Record<AuditEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  venue: "venues",
  event: "events",
};

const NAME_FIELD: Record<AuditEntityType, string> = {
  person: "full_name",
  ensemble: "name",
  venue: "name",
  event: "title",
};

const ENTITY_SELECT: Record<AuditEntityType, string> = {
  person:
    "id,slug,full_name,first_name,middle_name,last_name,roles,instrument,nationality,birth_date,death_date,website_url,is_verified",
  ensemble:
    "id,slug,name,type,founded_year,member_count,home_venue_id,website_url,is_verified",
  venue:
    "id,slug,name,address_street,address_zip,address_city,capacity,website_url",
  event:
    "id,slug,title,subtitle,start_datetime,end_datetime,duration_minutes,venue_id,organizer_id,ticket_url,website_url,price_min,price_max,is_free,status,program_id",
};

const AI_AUDIT_FUNCTION: AiFunctionDeclaration = {
  name: "report_entity_inconsistencies",
  description:
    "Prüft einen redaktionellen Klassik-Datensatz auf plausible Unstimmigkeiten, ohne ihn zu verändern.",
  parameters: {
    type: "object",
    properties: {
      summary: {
        type: "string",
        description:
          "Ein kurzer deutscher Gesamteindruck in höchstens zwei Sätzen.",
      },
      issues: {
        type: "array",
        items: {
          type: "object",
          properties: {
            severity: { type: "string", enum: ["critical", "warning", "info"] },
            category: {
              type: "string",
              enum: [
                "duplicate",
                "name",
                "spelling",
                "completeness",
                "contradiction",
                "plausibility",
              ],
            },
            message: {
              type: "string",
              description:
                "Konkrete, verständliche Beschreibung der Auffälligkeit.",
            },
            suggestion: {
              type: "string",
              description:
                "Konservativer Prüfschritt oder Korrekturvorschlag, niemals eine automatische Änderung.",
            },
            relatedId: {
              type: "string",
              description:
                "Nur die ID eines gelieferten Vergleichskandidaten; sonst weglassen.",
            },
            relatedName: {
              type: "string",
              description:
                "Nur der Name des gelieferten Vergleichskandidaten; sonst weglassen.",
            },
            confidence: {
              type: "number",
              description: "Sicherheit zwischen 0 und 1.",
            },
          },
          required: ["severity", "category", "message"],
        },
      },
    },
    required: ["summary", "issues"],
  },
};

const jsonHeaders = { "content-type": "application/json; charset=utf-8" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Nur POST ist erlaubt." }, 405);
  }
  const authorized = await isEditor(req);
  if (!authorized) {
    return json({ error: "Keine Admin- oder Redaktionsberechtigung." }, 403);
  }
  if (!hasAnyAiProviderConfigured()) {
    return json({ error: "Kein AI-Provider-Secret gesetzt." }, 500);
  }

  let body: { entityType?: unknown; entityId?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "Ungültiger Request-Body." }, 400);
  }
  const entityType = body.entityType as AuditEntityType;
  const entityId = typeof body.entityId === "string" ? body.entityId : "";
  if (!TABLE[entityType] || !entityId) {
    return json({ error: "entityType und entityId sind erforderlich." }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const { data: entity, error } = await supabase
    .from(TABLE[entityType])
    .select(ENTITY_SELECT[entityType])
    .eq("id", entityId)
    .maybeSingle();
  if (error || !entity) {
    return json({ error: error?.message ?? "Eintrag nicht gefunden." }, 404);
  }

  // Tabelle und Select werden anhand des geprüften entityType dynamisch
  // gewählt. Supabase kann diesen Zusammenhang typseitig nicht abbilden;
  // der geladene Datensatz ist ab hier dennoch immer ein JSON-Objekt.
  const entityRecord = entity as unknown as JsonRecord;
  const name = String(entityRecord[NAME_FIELD[entityType]] ?? "");
  const candidates = await loadCandidates(
    supabase,
    entityType,
    entityRecord,
    name,
  );
  const ruleIssues = [
    ...basicNameIssues(entityType, name),
    ...duplicateIssues(candidates),
    ...entitySpecificIssues(entityType, entityRecord),
  ];

  const response = await callAiFunction(
    "Du prüfst redaktionelle Datensätze einer Klassik-App auf Unstimmigkeiten. Du veränderst nichts. " +
      "Melde nur plausible, konkret erklärbare Auffälligkeiten. Ein ungewöhnlicher Künstlername kann korrekt sein; formuliere dann lediglich einen Prüfhinsweis. " +
      "Duplikate darfst du ausschließlich unter den ausdrücklich gelieferten Vergleichskandidaten nennen und relatedId muss exakt aus diesen Kandidaten stammen. " +
      "Erfinde keine Biografien, Daten, Personen oder korrekten Schreibweisen. Fehlende optionale Felder sind nicht automatisch Fehler. " +
      "Achte besonders auf gekürzte Personennamen, mögliche Tippfehler, widersprüchliche Daten, unplausible Zahlen und echte Dubletten.",
    JSON.stringify(
      { entityType, entity: entityRecord, comparisonCandidates: candidates },
      null,
      2,
    ),
    AI_AUDIT_FUNCTION,
  );

  const candidateById = new Map(
    candidates.map((candidate) => [candidate.id, candidate]),
  );
  const aiIssues = parseAiIssues(response?.args.issues, candidateById);
  const issues = deduplicateIssues([...ruleIssues, ...aiIssues]).slice(0, 16);
  const criticalCount = issues.filter((issue) =>
    issue.severity === "critical"
  ).length;
  const warningCount =
    issues.filter((issue) => issue.severity === "warning").length;
  const summary =
    typeof response?.args.summary === "string" && response.args.summary.trim()
      ? response.args.summary.trim().slice(0, 500)
      : issues.length === 0
      ? "Keine konkreten Unstimmigkeiten gefunden."
      : `${criticalCount} kritische und ${warningCount} weitere prüfenswerte Auffälligkeiten gefunden.`;

  return json({
    status: issues.length === 0 ? "clean" : "issues",
    summary,
    issues,
    checkedAt: new Date().toISOString(),
    provider: response?.provider ?? null,
  });
});

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: jsonHeaders });
}

async function isEditor(req: Request): Promise<boolean> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return false;
  const client = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: userData, error: userError } = await client.auth.getUser();
  if (userError || !userData.user || userData.user.is_anonymous) return false;
  const { data, error } = await client.rpc("is_admin_or_editor");
  return !error && data === true;
}

async function loadCandidates(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entityType: AuditEntityType,
  entity: JsonRecord,
  name: string,
) {
  if (entityType === "event") {
    const startDate = typeof entity.start_datetime === "string"
      ? new Date(entity.start_datetime)
      : null;
    if (!startDate || Number.isNaN(startDate.getTime())) return [];
    const from = new Date(startDate.getTime() - 3 * 60 * 60 * 1000)
      .toISOString();
    const to = new Date(startDate.getTime() + 3 * 60 * 60 * 1000).toISOString();
    const { data } = await supabase
      .from("events")
      .select("id,title,start_datetime,venue_id,venues(name)")
      .neq("id", String(entity.id))
      .gte("start_datetime", from)
      .lte("start_datetime", to)
      .limit(100);
    const rows = (data ?? []) as Array<
      JsonRecord & { venues?: { name?: string } | null }
    >;
    const eventCandidates = rows.flatMap((row): NameCandidate[] => {
      const title = typeof row.title === "string" ? row.title : "";
      const similarity = nameSimilarity(name, title);
      if (similarity < 0.72) return [];
      const sameVenue = Boolean(
        entity.venue_id && row.venue_id === entity.venue_id,
      );
      if (!sameVenue && similarity < 0.9) return [];
      return [{
        id: String(row.id),
        name: title,
        context: `${String(row.start_datetime ?? "")}${
          row.venues?.name ? ` · ${row.venues.name}` : ""
        }`,
      }];
    });
    return findNameCandidates(String(entity.id), name, eventCandidates).map((
      candidate,
    ) => ({
      ...candidate,
      reason: `${candidate.reason}; Termin innerhalb von drei Stunden${
        entity.venue_id ? " und passender Venue-Kontext" : ""
      }`,
    }));
  }

  const select = entityType === "person"
    ? "id,full_name,birth_date,death_date,instrument"
    : entityType === "ensemble"
    ? "id,name,type,founded_year"
    : "id,name,address_street,address_zip,address_city";
  const { data } = await supabase.from(TABLE[entityType]).select(select).limit(
    5000,
  );
  const rows = (data ?? []) as JsonRecord[];
  const names: NameCandidate[] = rows.map((row) => {
    const candidateName = String(row[NAME_FIELD[entityType]] ?? "");
    const context = entityType === "person"
      ? [row.birth_date, row.instrument].filter(Boolean).join(" · ")
      : entityType === "ensemble"
      ? [row.type, row.founded_year].filter(Boolean).join(" · ")
      : [row.address_street, row.address_zip, row.address_city].filter(Boolean)
        .join(", ");
    return { id: String(row.id), name: candidateName, context };
  });
  return findNameCandidates(String(entity.id), name, names);
}

function entitySpecificIssues(
  entityType: AuditEntityType,
  entity: JsonRecord,
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

function parseAiIssues(
  raw: unknown,
  candidates: Map<string, { id: string; name: string }>,
): AuditIssue[] {
  if (!Array.isArray(raw)) return [];
  const allowedSeverity = new Set(["critical", "warning", "info"]);
  const allowedCategory = new Set([
    "duplicate",
    "name",
    "spelling",
    "completeness",
    "contradiction",
    "plausibility",
  ]);
  return raw.slice(0, 12).flatMap((item, index): AuditIssue[] => {
    if (!item || typeof item !== "object") return [];
    const value = item as JsonRecord;
    const message = typeof value.message === "string"
      ? value.message.trim().slice(0, 500)
      : "";
    const severity =
      typeof value.severity === "string" && allowedSeverity.has(value.severity)
        ? value.severity
        : "warning";
    const category =
      typeof value.category === "string" && allowedCategory.has(value.category)
        ? value.category
        : "plausibility";
    if (!message) return [];
    const requestedRelatedId = typeof value.relatedId === "string"
      ? value.relatedId
      : null;
    const candidate = requestedRelatedId
      ? candidates.get(requestedRelatedId)
      : null;
    const confidence =
      typeof value.confidence === "number" && Number.isFinite(value.confidence)
        ? Math.min(Math.max(value.confidence, 0), 1)
        : null;
    return [{
      id: `ai-${index}-${crypto.randomUUID()}`,
      severity: severity as AuditIssue["severity"],
      category: category as AuditIssue["category"],
      message,
      suggestion: typeof value.suggestion === "string"
        ? value.suggestion.trim().slice(0, 500) || null
        : null,
      relatedId: candidate?.id ?? null,
      relatedName: candidate?.name ?? null,
      confidence,
      source: "ai",
    }];
  });
}
