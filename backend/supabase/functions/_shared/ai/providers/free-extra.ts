// Erstellt von Claude Code (14.11.2026): weitere kostenlose Anbieter mit
// OpenAI-kompatibler API als Rückfall für die Klangradar KI. Jeder Anbieter
// ist nur aktiv, wenn sein Secret gesetzt ist (sonst übersprungen).
//   GROQ_API_KEY        console.groq.com – kostenloser Tarif, sehr schnell
//   OPENROUTER_API_KEY  openrouter.ai – „:free“-Modelle ohne Kosten
//   MISTRAL_API_KEY     console.mistral.ai – kostenloser „Experiment“-Tarif
// Modell-IDs bei einem 404 über GET …/models des Anbieters prüfen.
import { createOpenAiCompatibleProvider } from "./openai-compatible.ts";

export const groqProvider = createOpenAiCompatibleProvider({
  name: "groq",
  envKey: "GROQ_API_KEY",
  apiBase: "https://api.groq.com/openai/v1/chat/completions",
  model: "llama-3.3-70b-versatile",
});

export const openRouterProvider = createOpenAiCompatibleProvider({
  name: "openrouter",
  envKey: "OPENROUTER_API_KEY",
  apiBase: "https://openrouter.ai/api/v1/chat/completions",
  model: "meta-llama/llama-3.3-70b-instruct:free",
});

export const mistralProvider = createOpenAiCompatibleProvider({
  name: "mistral",
  envKey: "MISTRAL_API_KEY",
  apiBase: "https://api.mistral.ai/v1/chat/completions",
  model: "mistral-small-latest",
});
