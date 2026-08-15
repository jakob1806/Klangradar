"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import {
  applyEditorialAiProposals,
  chatWithEditorialAi,
  type EditorialAiProposal,
} from "@/lib/editorial-ai-actions";

export type AuditableEntityType = "person" | "ensemble" | "venue" | "event";

export interface EntityAuditPageResult {
  checkedInPage: number;
  flaggedInPage: number;
  totalCount: number;
  done: boolean;
  aiUsed: boolean;
  aiFailures: number;
}

export interface EntityAuditCorrection {
  answer: string | null;
  proposals: EditorialAiProposal[];
  generatedAt: string;
}

type StoredAuditIssue = Record<string, unknown> & {
  message?: string;
  suggestion?: string | null;
  aiCorrection?: EntityAuditCorrection;
};

function functionsUrl(path: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${path}`;
}

/**
 * Generalisierte Massenprüfung (siehe backend/supabase/functions/
 * audit-entities-bulk) für Personen, Ensembles, Venues und Veranstaltungen —
 * vormals nur für Personen (audit-persons-bulk, jetzt entfernt). Seitenweise
 * aus demselben Grund: bei vielen Datensätzen reißt ein einziger Aufruf den
 * Timeout.
 */
export async function runEntityAuditPage(
  entityType: AuditableEntityType,
  offset: number,
): Promise<EntityAuditPageResult> {
  const supabase = await createClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user || userData.user.is_anonymous) {
    throw new Error("Die Admin-Sitzung ist abgelaufen. Bitte erneut anmelden.");
  }
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  const accessToken = sessionData.session?.access_token;
  if (sessionError || !accessToken) {
    throw new Error("Die Admin-Sitzung konnte nicht gelesen werden. Bitte erneut anmelden.");
  }

  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  let response: Response;
  try {
    response = await fetch(functionsUrl("audit-entities-bulk"), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey,
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ entityType, offset }),
      signal: AbortSignal.timeout(90_000),
    });
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "TimeoutError";
    throw new Error(timedOut ? "Zeitüberschreitung — bitte erneut versuchen." : `Prüfung nicht erreichbar: ${err}`);
  }

  const data: unknown = await response.json().catch(() => null);
  if (!response.ok || !data || typeof data !== "object") {
    const message = data && typeof data === "object" && "error" in data && typeof data.error === "string"
      ? data.error
      : `Prüfung fehlgeschlagen (HTTP ${response.status}).`;
    throw new Error(message);
  }

  const result = data as Record<string, unknown>;
  return {
    checkedInPage: typeof result.checkedInPage === "number" ? result.checkedInPage : 0,
    flaggedInPage: typeof result.flaggedInPage === "number" ? result.flaggedInPage : 0,
    totalCount: typeof result.totalCount === "number" ? result.totalCount : 0,
    done: result.done === true,
    aiUsed: result.aiUsed === true,
    aiFailures: typeof result.aiFailures === "number" ? result.aiFailures : 0,
  };
}

export async function resolveEntityAuditFlag(id: string): Promise<void> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("entity_audit_flags")
    .update({ status: "resolved", resolved_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/qualitaetspruefung");
}

export interface BulkAuditActionResult {
  completed: number;
  skipped: number;
  failed: number;
  errors?: string[];
}

export interface AuditPreparationResult {
  generated: number;
  existing: number;
  empty: number;
  failed: number;
  errors: string[];
}

export async function resolveEntityAuditFlags(ids: string[]): Promise<BulkAuditActionResult> {
  const uniqueIds = [...new Set(ids)].slice(0, 200);
  if (uniqueIds.length === 0) return { completed: 0, skipped: 0, failed: 0 };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("entity_audit_flags")
    .update({ status: "resolved", resolved_at: new Date().toISOString() })
    .in("id", uniqueIds)
    .eq("status", "open")
    .select("id");
  if (error) throw new Error(error.message);
  revalidatePath("/qualitaetspruefung");
  const completed = data?.length ?? 0;
  return { completed, skipped: uniqueIds.length - completed, failed: 0 };
}

/** Übernimmt fuer mehrere ausgewaehlte Pruefeintraege alle ausreichend
 * sicheren KI-Feldvorschlaege. Fehlt ein gespeicherter Vorschlag, wird er
 * hier zuerst erzeugt. Das beseitigt den frueheren No-op: "Alle auswaehlen"
 * uebersprang still alle Zeilen, fuer die noch nie einzeln auf
 * "KI-Korrektur vorschlagen" geklickt worden war. */
export async function applyAllEntityAuditCorrections(ids: string[]): Promise<BulkAuditActionResult> {
  const uniqueIds = [...new Set(ids)].slice(0, 100);
  if (uniqueIds.length === 0) return { completed: 0, skipped: 0, failed: 0 };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("entity_audit_flags")
    .select("id, entity_type, entity_id, issues, status")
    .in("id", uniqueIds)
    .eq("status", "open");
  if (error) throw new Error(error.message);

  const rows = data ?? [];
  let completed = 0;
  let skipped = uniqueIds.length - rows.length;
  let failed = 0;
  const errors: string[] = [];
  let cursor = 0;
  const worker = async () => {
    while (cursor < rows.length) {
      const row = rows[cursor++];
      const issues = Array.isArray(row.issues) ? (row.issues as StoredAuditIssue[]) : [];
      try {
        let correction = issues.find((issue) => issue.aiCorrection)?.aiCorrection;
        if (!correction || !Array.isArray(correction.proposals) || correction.proposals.length === 0) {
          const messages = issues.map((issue) => issue.message).filter((value): value is string => Boolean(value));
          const suggestions = issues.map((issue) => issue.suggestion).filter((value): value is string => Boolean(value));
          correction = await suggestEntityAuditCorrection(
            row.id,
            row.entity_type as AuditableEntityType,
            row.entity_id,
            messages.join(" ") || "Automatisch erkanntes Datenqualitaetsproblem",
            suggestions.join(" ") || null,
            true,
          );
        }
        const proposals = (correction.proposals ?? []).filter((proposal) => proposal.confidence !== "unclear");
        if (proposals.length === 0) {
          skipped += 1;
          continue;
        }
        await applyEditorialAiProposals(
          row.entity_type as AuditableEntityType,
          row.entity_id,
          proposals,
        );
        const { error: resolveError } = await supabase
          .from("entity_audit_flags")
          .update({ status: "resolved", resolved_at: new Date().toISOString() })
          .eq("id", row.id)
          .eq("status", "open");
        if (resolveError) throw resolveError;
        completed += 1;
      } catch (error) {
        failed += 1;
        errors.push(error instanceof Error ? error.message : "Unbekannter Fehler");
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(2, rows.length) }, worker));
  revalidatePath("/qualitaetspruefung");
  return { completed, skipped, failed, errors: [...new Set(errors)].slice(0, 3) };
}

/** Bereitet fehlende Vorschläge serverseitig in kleinen Batches vor. Leere
 * Altantworten gelten nicht mehr als fertiger Cache und werden neu
 * recherchiert. Der Aufrufer kann die nächsten IDs nach einem Refresh
 * fortsetzen, ohne bereits erfolgreiche Vorschläge erneut zu berechnen. */
export async function prepareEntityAuditCorrections(ids: string[]): Promise<AuditPreparationResult> {
  const uniqueIds = [...new Set(ids)].slice(0, 12);
  const result: AuditPreparationResult = { generated: 0, existing: 0, empty: 0, failed: 0, errors: [] };
  if (uniqueIds.length === 0) return result;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("entity_audit_flags")
    .select("id, entity_type, entity_id, issues, status")
    .in("id", uniqueIds)
    .eq("status", "open");
  if (error) throw new Error(error.message);

  const rows = data ?? [];
  let cursor = 0;
  const worker = async () => {
    while (cursor < rows.length) {
      const row = rows[cursor++];
      const issues = Array.isArray(row.issues) ? row.issues as StoredAuditIssue[] : [];
      const stored = issues.find((issue) => issue.aiCorrection)?.aiCorrection;
      if (stored?.proposals?.length) {
        result.existing += 1;
        continue;
      }
      try {
        const messages = issues.map((issue) => issue.message).filter((value): value is string => Boolean(value));
        const suggestions = issues.map((issue) => issue.suggestion).filter((value): value is string => Boolean(value));
        const correction = await suggestEntityAuditCorrection(
          row.id,
          row.entity_type as AuditableEntityType,
          row.entity_id,
          messages.join(" ") || "Automatisch erkanntes Datenqualitätsproblem",
          suggestions.join(" ") || null,
          Boolean(stored),
        );
        if (correction.proposals.length > 0) result.generated += 1;
        else result.empty += 1;
      } catch (cause) {
        result.failed += 1;
        result.errors.push(cause instanceof Error ? cause.message : "Unbekannter Fehler");
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(3, rows.length) }, worker));
  revalidatePath("/qualitaetspruefung");
  result.errors = [...new Set(result.errors)].slice(0, 3);
  return result;
}

export async function finishEntityAudit(): Promise<void> {
  revalidatePath("/qualitaetspruefung");
}

/** Erzeugt den bisher manuellen KI-Korrekturvorschlag und speichert ihn im
 * Prüfeintrag. Dadurch wird dieselbe Recherche beim Tab-Wechsel/Reload nicht
 * erneut berechnet. Die eigentliche Datenänderung bleibt weiterhin hinter
 * der expliziten redaktionellen Freigabe im UI. */
export async function suggestEntityAuditCorrection(
  flagId: string,
  entityType: AuditableEntityType,
  entityId: string,
  issueMessage: string,
  issueSuggestion?: string | null,
  force = false,
): Promise<EntityAuditCorrection> {
  const supabase = await createClient();
  const { data: flag, error: flagError } = await supabase
    .from("entity_audit_flags")
    .select("issues, status")
    .eq("id", flagId)
    .maybeSingle();
  if (flagError) throw new Error(flagError.message);
  if (!flag || flag.status !== "open") throw new Error("Die Auffälligkeit ist nicht mehr offen.");

  const issues = Array.isArray(flag.issues) ? (flag.issues as StoredAuditIssue[]) : [];
  const stored = issues.find((issue) => issue.aiCorrection)?.aiCorrection;
  if (!force && stored?.proposals?.length) return stored;

  const message = `Behebe folgendes automatisch erkanntes Datenqualitätsproblem: "${issueMessage}"` +
    (issueSuggestion ? ` Hinweis: ${issueSuggestion}` : "") +
    " Schlage den korrigierten Wert für das betroffene Feld vor, recherchiere falls nötig im Web.";
  const result = await chatWithEditorialAi(entityType, entityId, message);
  const correction: EntityAuditCorrection = {
    answer: typeof result.answer === "string" ? result.answer : null,
    proposals: Array.isArray(result.proposals) ? (result.proposals as EditorialAiProposal[]) : [],
    generatedAt: new Date().toISOString(),
  };

  // Noch einmal frisch lesen: Während der Recherche kann ein neuer Auditlauf
  // die Issues aktualisiert haben. So überschreiben wir diese nicht mit dem
  // Stand von vor der KI-Anfrage.
  const { data: fresh, error: freshError } = await supabase
    .from("entity_audit_flags")
    .select("issues, status")
    .eq("id", flagId)
    .maybeSingle();
  if (freshError) throw new Error(freshError.message);
  if (!fresh || fresh.status !== "open") return correction;
  const freshIssues = Array.isArray(fresh.issues) ? (fresh.issues as StoredAuditIssue[]) : [];
  if (freshIssues.length === 0) return correction;
  const nextIssues = freshIssues.map((issue, index) =>
    index === 0 ? { ...issue, aiCorrection: correction } : issue,
  );
  const { error: updateError } = await supabase
    .from("entity_audit_flags")
    .update({ issues: nextIssues })
    .eq("id", flagId)
    .eq("status", "open");
  if (updateError) throw new Error(updateError.message);
  revalidatePath("/qualitaetspruefung");
  return correction;
}
