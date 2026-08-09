"use server";

import { createClient } from "@/lib/supabase/server";

export type AuditEntityType = "person" | "ensemble" | "venue" | "event";
export type AuditSeverity = "critical" | "warning" | "info";

export interface AuditIssue {
  id: string;
  severity: AuditSeverity;
  category: "duplicate" | "name" | "spelling" | "completeness" | "contradiction" | "plausibility";
  message: string;
  suggestion?: string | null;
  relatedId?: string | null;
  relatedName?: string | null;
  confidence?: number | null;
  source: "rule" | "ai";
}

export interface AuditResult {
  status: "clean" | "issues";
  summary: string;
  issues: AuditIssue[];
  checkedAt: string;
  provider: string | null;
}

const ENTITY_TYPES = new Set<AuditEntityType>(["person", "ensemble", "venue", "event"]);

function functionsUrl(path: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${path}`;
}

function isAuditResult(value: unknown): value is AuditResult {
  if (!value || typeof value !== "object") return false;
  const result = value as Partial<AuditResult>;
  return (
    (result.status === "clean" || result.status === "issues") &&
    typeof result.summary === "string" &&
    typeof result.checkedAt === "string" &&
    Array.isArray(result.issues)
  );
}

/**
 * Führt eine rein lesende Plausibilitäts- und Dublettenprüfung aus.
 * Der Benutzer-JWT wird bewusst an die Edge Function weitergereicht, damit
 * dort die Admin-/Redaktionsrolle geprüft werden kann. Es wird kein Datensatz
 * geändert und deshalb auch kein Pfad revalidiert.
 */
export async function auditEntity(entityType: AuditEntityType, entityId: string): Promise<AuditResult> {
  if (!ENTITY_TYPES.has(entityType) || !entityId.trim()) {
    throw new Error("Ungültiger Eintrag für die KI-Prüfung.");
  }

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
  const response = await fetch(functionsUrl("audit-entity"), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ entityType, entityId }),
    signal: AbortSignal.timeout(60_000),
  });

  const data: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const message = data && typeof data === "object" && "error" in data && typeof data.error === "string"
      ? data.error
      : `KI-Prüfung fehlgeschlagen (HTTP ${response.status}).`;
    throw new Error(message);
  }
  if (!isAuditResult(data)) {
    throw new Error("Die KI-Prüfung hat eine ungültige Antwort geliefert.");
  }
  return data;
}
