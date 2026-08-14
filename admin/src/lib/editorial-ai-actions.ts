"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type EditorialAiEntityType = "event" | "person" | "ensemble" | "work" | "venue";
export type EditorialAiProposal = {
  field: string;
  value: unknown;
  confidence: "confirmed" | "likely" | "unclear";
  rationale?: string;
  sourceUrls?: string[];
};

async function callAssistant(payload: Record<string, unknown>) {
  const supabase = await createClient();
  const [{ data: user }, { data: session }] = await Promise.all([
    supabase.auth.getUser(),
    supabase.auth.getSession(),
  ]);
  if (!user.user || !session.session?.access_token) throw new Error("Bitte erneut anmelden.");
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  const response = await fetch(`${baseUrl}/functions/v1/editorial-ai-assistant`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey,
      Authorization: `Bearer ${session.session.access_token}`,
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(60_000),
  });
  const data = await response.json().catch(() => null);
  if (!response.ok || !data) throw new Error(data?.error ?? `Gemini-Anfrage fehlgeschlagen (HTTP ${response.status}).`);
  return data;
}

export async function loadEditorialAi(entityType: EditorialAiEntityType, entityId: string) {
  return callAssistant({ action: "load", entityType, entityId });
}

export async function chatWithEditorialAi(entityType: EditorialAiEntityType, entityId: string, message: string) {
  return callAssistant({ action: "chat", entityType, entityId, message });
}

const ENTITY_ROUTE: Record<EditorialAiEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  event: "events",
  work: "works",
  venue: "venues",
};

export async function applyEditorialAiProposals(entityType: EditorialAiEntityType, entityId: string, proposals: EditorialAiProposal[]) {
  const result = await callAssistant({ action: "apply", entityType, entityId, proposals });
  revalidatePath(`/${ENTITY_ROUTE[entityType]}/${entityId}`);
  return result;
}

export async function updateEditorialAiMemory(instructions: string) {
  return callAssistant({ action: "update_memory", instructions });
}
