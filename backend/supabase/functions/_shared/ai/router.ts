// AI-Provider-Router mit Fallback-Kette (Architektur-Dokument Abschnitt 9.1).
// Grund: an einem einzigen Nachmittag sind Gemini (Kontingent 0, dann nur
// 20 Anfragen/Tag), Cerebras (HTTP 402 trotz beworbenem Free-Tier) und
// potenziell weitere Free-Tier-Provider ausgefallen — ein Single-Provider-
// Design ist ein SPOF. Statt die Pipeline an einen Provider zu binden, kennt
// der Rest der Codebase nur noch callAiFunction(); welcher Provider
// tatsächlich antwortet, ist Implementierungsdetail dieser Datei.
//
// Reihenfolge in PROVIDERS = Fallback-Reihenfolge. Ein Provider ohne
// gesetztes Secret liefert selbst null zurück (siehe die einzelnen
// providers/*.ts) — kein Vorab-Check nötig, der Router probiert die Kette
// einfach durch. Reihenfolge bewusst nicht von außen konfigurierbar
// (kein DB-Setting) gehalten, um die Kette einfach zu halten; sollte das
// nötig werden, hier PROVIDERS aus einem Supabase-Secret/Config lesen.

import type { AiFunctionDeclaration } from "./types.ts";
import { cerebrasProvider } from "./providers/cerebras.ts";
import { nvidiaProvider } from "./providers/nvidia.ts";
import { createGeminiProvider } from "./providers/gemini.ts";

const geminiProvider = createGeminiProvider();
const PROVIDERS = [cerebrasProvider, nvidiaProvider, geminiProvider];

export type { AiFunctionDeclaration };

/** True, wenn mindestens ein Provider-Secret gesetzt ist — für einen
 * schnellen Fail-Fast-Check am Funktionsanfang, statt erst nach N leeren
 * Versuchen pro Event zu merken, dass gar kein Key konfiguriert ist. */
export function hasAnyAiProviderConfigured(): boolean {
  return PROVIDERS.some((p) => !!Deno.env.get(p.envKey));
}

/** Probiert die Provider-Kette der Reihe nach durch, gibt die Argumente des
 * ersten erfolgreichen Aufrufs zurück (plus welcher Provider geantwortet
 * hat, fürs Debugging/Logging), oder null wenn alle fehlschlagen. */
export async function callAiFunction(
  system: string,
  user: string,
  fn: AiFunctionDeclaration,
  // deno-lint-ignore no-explicit-any
): Promise<{ args: Record<string, any>; provider: string } | null> {
  for (const provider of PROVIDERS) {
    const args = await provider.callFunction(system, user, fn);
    if (args) return { args, provider: provider.name };
  }
  return null;
}

/** Wissensfragen profitieren stärker von Geminis breitem Trainingswissen als
 * von den auf schnelle strukturierte Extraktion optimierten Erstprovidern.
 * Gemini wird hierfür bevorzugt, die robuste Fallback-Kette bleibt erhalten.
 */
export async function callAiFunctionPreferGemini(
  system: string,
  user: string,
  fn: AiFunctionDeclaration,
  // deno-lint-ignore no-explicit-any
): Promise<{ args: Record<string, any>; provider: string } | null> {
  for (const provider of [geminiProvider, cerebrasProvider, nvidiaProvider]) {
    const args = await provider.callFunction(system, user, fn);
    if (args) return { args, provider: provider.name };
  }
  return null;
}
