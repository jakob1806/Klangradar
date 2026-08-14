import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  type AiFunctionDeclaration,
  callAiFunction,
  hasAnyAiProviderConfigured,
} from "../_shared/ai/router.ts";
import {
  AUDIT_ENTITY_SELECT,
  AUDIT_NAME_FIELD,
  AUDIT_TABLE,
  type AuditEntityType,
  type AuditIssue,
  basicNameIssues,
  entitySpecificIssues,
} from "../audit-entity/heuristics.ts";

// Generalisierte Massenprüfung über alle vier Qualitätsprüfungs-
// Entitätstypen (siehe audit-persons-bulk, aus dem diese Function
// hervorgegangen ist — dort nur für Personen). Seitenweise aus demselben
// Grund: bei tausenden Datensätzen würde eine einzige Invocation den
// Timeout reißen, weil pro KI-Batch bis zu 3 Provider probiert werden
// (siehe _shared/ai/router.ts).
const PAGE_SIZE = 200;
const BATCH_SIZE = 40;
const CONCURRENCY = 4;

const ENTITY_LABEL: Record<AuditEntityType, string> = {
  person: "Personen (Solist:innen, Dirigent:innen, Komponist:innen)",
  ensemble: "Ensembles (Orchester, Chöre)",
  venue: "Veranstaltungsorte",
  event: "Veranstaltungstitel",
};

const NOT_A_NAME_HINT: Record<AuditEntityType, string> = {
  person:
    "erkennbar fehlender Nachname (nur ein Vorname oder nur ein Nachname), offensichtlich kein Personenname " +
    "(z.B. Ensemble- oder Organisationsname), Test-/Platzhaltertext, oder eindeutig fehlerhafte/kaputte Zeichenketten",
  ensemble:
    "offensichtlich kein Ensemblename (z.B. eine Einzelperson oder eine Institution), Test-/Platzhaltertext, " +
    "oder eindeutig fehlerhafte/kaputte Zeichenketten",
  venue:
    "offensichtlich kein Veranstaltungsort (z.B. eine Person oder ein Werktitel), Test-/Platzhaltertext, " +
    "oder eindeutig fehlerhafte/kaputte Zeichenketten",
  event:
    "ein offensichtlich unvollständiger oder abgebrochener Titel, reiner Platzhaltertext (\"Test\", \"TBA\"), " +
    "oder eindeutig kaputte/verstümmelte Zeichenketten (z.B. HTML-Reste, doppelte Fragmente)",
};

function aiFunctionFor(entityType: AuditEntityType): AiFunctionDeclaration {
  return {
    name: "flag_unusual_entity_names",
    description:
      `Markiert Einträge aus einer nummerierten Liste von ${ENTITY_LABEL[entityType]}, die strukturell auffällig sind.`,
    parameters: {
      type: "object",
      properties: {
        flagged: {
          type: "array",
          items: {
            type: "object",
            properties: {
              index: {
                type: "number",
                description: "Der 0-basierte Index aus der gelieferten Liste.",
              },
              severity: { type: "string", enum: ["critical", "warning", "info"] },
              reason: {
                type: "string",
                description: "Kurze deutsche Begründung, konkret auf diesen Eintrag bezogen.",
              },
            },
            required: ["index", "reason"],
          },
        },
      },
      required: ["flagged"],
    },
  };
}

const jsonHeaders = { "content-type": "application/json; charset=utf-8" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Nur POST ist erlaubt." }, 405);
  }
  const authorized = await isEditor(req);
  if (!authorized) {
    return json({ error: "Keine Admin- oder Redaktionsberechtigung." }, 403);
  }

  let body: { entityType?: unknown; offset?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    // leerer Body ist ok, dann Standardwerte
  }
  const entityType = body.entityType as AuditEntityType;
  if (!AUDIT_TABLE[entityType]) {
    return json({ error: "entityType muss person, ensemble, venue oder event sein." }, 400);
  }
  const offset = typeof body.offset === "number" && body.offset >= 0 ? body.offset : 0;
  const nameField = AUDIT_NAME_FIELD[entityType];

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: rowsData, error, count } = await supabase
    .from(AUDIT_TABLE[entityType])
    .select(AUDIT_ENTITY_SELECT[entityType], { count: "exact" })
    .order(nameField)
    .range(offset, offset + PAGE_SIZE - 1);
  if (error) {
    return json({ error: error.message }, 500);
  }

  const rows = (rowsData ?? []) as unknown as Record<string, unknown>[];
  const totalCount = count ?? offset + rows.length;
  const issuesByEntityId = new Map<string, AuditIssue[]>();

  for (const entity of rows) {
    const id = String(entity.id);
    const name = String(entity[nameField] ?? "");
    const ruleIssues = [
      ...basicNameIssues(entityType, name),
      ...entitySpecificIssues(entityType, entity),
    ];
    if (ruleIssues.length > 0) issuesByEntityId.set(id, ruleIssues);
  }

  const useAi = hasAnyAiProviderConfigured();
  let aiFailures = 0;
  if (useAi && rows.length > 0) {
    const batches: Record<string, unknown>[][] = [];
    for (let i = 0; i < rows.length; i += BATCH_SIZE) {
      batches.push(rows.slice(i, i + BATCH_SIZE));
    }
    const aiFunction = aiFunctionFor(entityType);

    let cursor = 0;
    const worker = async () => {
      while (cursor < batches.length) {
        const batchIndex = cursor++;
        const batch = batches[batchIndex];
        if (!batch) continue;
        try {
          const response = await callAiFunction(
            `Du prüfst eine Liste von ${ENTITY_LABEL[entityType]} aus der Stammdatenbank einer Klassik-App auf strukturelle Auffälligkeiten. ` +
              `Melde nur Einträge mit: ${NOT_A_NAME_HINT[entityType]}. ` +
              "Ein ungewöhnlicher, seltener oder nicht-deutscher, aber plausibler Eintrag ist KEIN Grund zum Melden — im Zweifel nicht melden. " +
              "Gib ausschließlich den Index aus der Liste zurück, keine erfundenen Namen.",
            JSON.stringify(
              batch.map((entity, index) => ({ index, name: String(entity[nameField] ?? "") })),
            ),
            aiFunction,
          );
          const flagged = Array.isArray(response?.args.flagged)
            ? response.args.flagged
            : [];
          for (const entry of flagged) {
            if (!entry || typeof entry !== "object") continue;
            const value = entry as Record<string, unknown>;
            const index = typeof value.index === "number" ? value.index : -1;
            const entity = batch[index];
            const reason = typeof value.reason === "string" ? value.reason.trim() : "";
            if (!entity || !reason) continue;
            const id = String(entity.id);
            const severity = value.severity === "critical" || value.severity === "info"
              ? value.severity
              : "warning";
            const existing = issuesByEntityId.get(id) ?? [];
            existing.push({
              id: `ai-bulk-${id}`,
              severity,
              category: "plausibility",
              message: reason.slice(0, 500),
              suggestion: null,
              source: "ai",
            });
            issuesByEntityId.set(id, existing);
          }
        } catch (err) {
          aiFailures++;
          console.error(`audit-entities-bulk batch ${batchIndex}: ${err}`);
        }
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(CONCURRENCY, batches.length) }, worker),
    );
  }

  const flaggedIds = [...issuesByEntityId.keys()];
  const nameById = new Map(rows.map((entity) => [String(entity.id), String(entity[nameField] ?? "")]));

  if (flaggedIds.length > 0) {
    const upsertRows = flaggedIds.map((entityId) => ({
      entity_type: entityType,
      entity_id: entityId,
      display_name: nameById.get(entityId) ?? "",
      issues: issuesByEntityId.get(entityId),
      status: "open",
      resolved_at: null,
    }));
    const { error: upsertError } = await supabase
      .from("entity_audit_flags")
      .upsert(upsertRows, { onConflict: "entity_type,entity_id" });
    if (upsertError) {
      return json({ error: upsertError.message }, 500);
    }
  }

  // Innerhalb dieser Seite geprüfte Einträge, die jetzt keine Auffälligkeit
  // mehr haben, gelten als erledigt und werden entfernt — beschränkt auf
  // die IDs dieser Seite, damit spätere Seiten nicht versehentlich Treffer
  // früherer Seiten löschen.
  const cleanIds = rows.map((e) => String(e.id)).filter((id) => !issuesByEntityId.has(id));
  if (cleanIds.length > 0) {
    const { error: cleanupError } = await supabase
      .from("entity_audit_flags")
      .delete()
      .eq("entity_type", entityType)
      .in("entity_id", cleanIds);
    if (cleanupError) {
      console.error(`audit-entities-bulk cleanup: ${cleanupError.message}`);
    }
  }

  return json({
    status: "ok",
    entityType,
    offset,
    checkedInPage: rows.length,
    flaggedInPage: flaggedIds.length,
    totalCount,
    done: offset + rows.length >= totalCount,
    aiUsed: useAi,
    aiFailures,
    checkedAt: new Date().toISOString(),
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
