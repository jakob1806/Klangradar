// Google Gemini API — braucht als einziger Provider in dieser Kette eine
// Schema-Übersetzung: Gemini nutzt ein OpenAPI-Schema-Subset (type-Werte
// GROSSGESCHRIEBEN, `nullable: true` statt Weglassen aus `required`), alle
// anderen Provider (Cerebras, NVIDIA NIM) sind OpenAI-kompatibel und nehmen
// das gemeinsame AiFunctionDeclaration-Format direkt.
//
// GEMINI_MODEL auf "gemini-flash-lite-latest" (nicht "gemini-flash-latest"):
// Stand 2026-07 hat das volle Flash-Modell nur 20 Anfragen/Tag im Free-Tier,
// das "-lite"-Pendant ein deutlich größeres separates Kontingent (eigener
// Quota-Bucket pro Modell). Beide "-latest"-Alias statt fest versionierter
// Modellnamen, da Google einzelne Versionen regelmäßig deprecatet (siehe
// Git-Historie dieser Datei für den vorherigen 429/404-Vorfall).
//
// Braucht GEMINI_API_KEY als Supabase-Secret (Google AI Studio -> "Get API
// key").

import type { AiFunctionDeclaration, AiProvider } from "../types.ts";

const GEMINI_MODEL = "gemini-flash-lite-latest";
const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

// deno-lint-ignore no-explicit-any
function toGeminiSchema(schema: any): any {
  if (schema == null || typeof schema !== "object") return schema;
  if (Array.isArray(schema)) return schema.map(toGeminiSchema);

  // deno-lint-ignore no-explicit-any
  const out: Record<string, any> = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === "type" && typeof value === "string") {
      out.type = value.toUpperCase();
    } else if (key === "properties" && value && typeof value === "object") {
      out.properties = Object.fromEntries(
        // deno-lint-ignore no-explicit-any
        Object.entries(value as Record<string, any>).map(([k, v]) => [k, toGeminiSchema(v)]),
      );
    } else if (key === "items") {
      out.items = toGeminiSchema(value);
    } else {
      out[key] = value;
    }
  }

  // Felder, die nicht in `required` stehen, bekommen zusätzlich
  // `nullable: true` — Gemini lässt sonst keine wirklich optionalen Felder
  // zu (anders als Standard-JSON-Schema, wo Weglassen aus `required` genügt).
  if (out.type === "OBJECT" && Array.isArray(out.required) && out.properties) {
    for (const [propName, propSchema] of Object.entries(out.properties)) {
      if (!out.required.includes(propName) && propSchema && typeof propSchema === "object") {
        // deno-lint-ignore no-explicit-any
        (propSchema as any).nullable = true;
      }
    }
  }
  return out;
}

export function createGeminiProvider(): AiProvider {
  return {
    name: "gemini",
    envKey: "GEMINI_API_KEY",
    async callFunction(system: string, user: string, fn: AiFunctionDeclaration) {
      const apiKey = Deno.env.get("GEMINI_API_KEY");
      if (!apiKey) return null;

      const geminiFn = { name: fn.name, description: fn.description, parameters: toGeminiSchema(fn.parameters) };

      // Nutzerfeedback: "KI braucht sehr lange, um zu antworten" —
      // callAiFunctionPreferGemini probiert Gemini für JEDEN der zwei
      // Aufrufe pro Chat-Nachricht (Planung, dann Antwort) zuerst, bevor
      // Cerebras/NVIDIA drankommen. Bei einer der wiederholt dokumentierten
      // Gemini-Kontingentsperren (siehe Datei-Kopfkommentar) verbrannte das
      // bislang bis zu 2× 20s, bevor überhaupt ein funktionierender
      // Provider gefragt wurde. Anders als NVIDIA (dokumentiert 10-13s
      // normale Erfolgslatenz, siehe openai-compatible.ts) hat Gemini keine
      // bekannte reguläre Latenz nahe 20s — ein kürzeres Timeout betrifft
      // also nur den Fehlerfall, nicht normale erfolgreiche Aufrufe.
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 8000);

      let res: Response;
      try {
        res = await fetch(`${GEMINI_API_BASE}/${GEMINI_MODEL}:generateContent`, {
          method: "POST",
          headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: system }] },
            contents: [{ role: "user", parts: [{ text: user }] }],
            tools: [{ functionDeclarations: [geminiFn] }],
            tool_config: {
              function_calling_config: { mode: "ANY", allowed_function_names: [fn.name] },
            },
          }),
          signal: controller.signal,
        });
      } catch {
        return null;
      } finally {
        clearTimeout(timeout);
      }
      if (!res.ok) return null;

      // deno-lint-ignore no-explicit-any
      let data: any;
      try {
        data = await res.json();
      } catch {
        return null;
      }

      const parts = data?.candidates?.[0]?.content?.parts;
      if (!Array.isArray(parts)) return null;
      // deno-lint-ignore no-explicit-any
      const withCall = parts.find((p: any) => p != null && typeof p === "object" && p.functionCall);
      const call = withCall?.functionCall;
      if (!call || call.name !== fn.name || typeof call.args !== "object") return null;
      return call.args;
    },
  };
}
