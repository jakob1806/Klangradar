// KI-Fallback für extract-event-from-url: wenn Schema.org keine Events
// liefert, schickt dies den sichtbaren Seitentext über die AI-Provider-
// Fallback-Kette (_shared/ai/router.ts) und bittet um strukturierte
// Event-Extraktion. Eine Seite kann EIN einzelnes Konzert zeigen oder ein
// GANZES Programm mit vielen Terminen — beides landet als jeweils ein
// Eintrag pro echtem Termin im selben events-Array, das Function-Schema
// unten unterscheidet nicht zwischen beiden Fällen.
//
// Braucht mindestens eines der in _shared/ai/router.ts verdrahteten
// Provider-Secrets — ohne jeden Key liefert diese Funktion einen klaren
// Fehler statt eines still leeren Ergebnisses.

import {
  type AiFunctionDeclaration,
  callAiFunction,
  hasAnyAiProviderConfigured,
} from "../_shared/ai/router.ts";
import type { RawEvent } from "../ingest-source/types.ts";

const MAX_TEXT_CHARS = 15000; // grobe Kosten-/Token-Begrenzung pro Aufruf

const EVENT_EXTRACTION_FUNCTION: AiFunctionDeclaration = {
  name: "extract_events",
  description: "Aus dem Seitentext erkannte Konzert-/Veranstaltungsdaten.",
  parameters: {
    type: "object",
    properties: {
      events: {
        type: "array",
        description:
          "Ein Eintrag pro erkanntem Konzert/Termin. Leeres Array, wenn keine echte Veranstaltung im Text erkennbar ist — kein Datum erfinden.",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            description: {
              type: "string",
              description:
                "Programm, Werke, Mitwirkende — falls im Text vorhanden, sonst weglassen.",
            },
            startDateTime: {
              type: "string",
              description:
                "ISO 8601 mit dem zum Termin gültigen Offset von Europe/Berlin (CET/CEST), z.B. 2026-08-15T19:30:00+02:00. Niemals eine zeitzonenlose Uhrzeit ausgeben. Fehlt im Text das Jahr, aus dem heutigen Datum ableiten (Veranstaltungsseiten zeigen kommende, nicht vergangene Termine).",
            },
            venueName: {
              type: "string",
              description: "Falls im Text erkennbar, sonst weglassen.",
            },
            venueAddress: {
              type: "string",
              description: "Falls im Text erkennbar, sonst weglassen.",
            },
            priceMin: {
              type: "number",
              description: "Falls im Text erkennbar, sonst weglassen.",
            },
            priceMax: {
              type: "number",
              description: "Falls im Text erkennbar, sonst weglassen.",
            },
            isFree: {
              type: "boolean",
              description: "Falls im Text erkennbar, sonst weglassen.",
            },
          },
          required: ["title", "startDateTime"],
        },
      },
    },
    required: ["events"],
  },
};

// deno-lint-ignore no-explicit-any
function isRecord(v: unknown): v is Record<string, any> {
  return v != null && typeof v === "object";
}

export async function extractEventsWithLlm(
  pageText: string,
  sourceUrl: string,
  todayIso: string,
): Promise<{ events: RawEvent[]; errors: string[] }> {
  if (!hasAnyAiProviderConfigured()) {
    return {
      events: [],
      errors: [
        "Kein AI-Provider-Secret gesetzt (CEREBRAS_API_KEY, NVIDIA_API_KEY oder GEMINI_API_KEY) — " +
        "KI-Fallback nicht verfügbar (Schema.org-Extraktion hat für diese Seite keine Events gefunden).",
      ],
    };
  }

  const truncated = pageText.slice(0, MAX_TEXT_CHARS);
  if (!truncated.trim()) {
    return {
      events: [],
      errors: ["Seitentext war leer — nichts zu extrahieren."],
    };
  }

  const response = await callAiFunction(
    `Heutiges Datum: ${todayIso}. Du extrahierst Konzert-/Veranstaltungsdaten aus dem Text ` +
      `einer Webseite. Ignoriere Navigation, Cookie-Hinweise, Werbung und sonstige nicht ` +
      `Event-bezogene Inhalte.`,
    `Seiten-URL: ${sourceUrl}\n\nSeitentext:\n${truncated}`,
    EVENT_EXTRACTION_FUNCTION,
  );
  const args = response?.args;

  if (!args) {
    return {
      events: [],
      errors: [
        "AI-Aufruf fehlgeschlagen (alle Provider) oder lieferte keinen extract_events-Aufruf.",
      ],
    };
  }

  const rawEvents = Array.isArray(args.events) ? args.events : [];
  const errors: string[] = [];
  const events: RawEvent[] = [];

  for (const e of rawEvents) {
    if (
      !isRecord(e) || typeof e.title !== "string" || !e.title.trim() ||
      typeof e.startDateTime !== "string"
    ) {
      errors.push(
        `Übersprungen: fehlender Titel oder Startzeit (${
          JSON.stringify(e).slice(0, 200)
        })`,
      );
      continue;
    }
    if (!/(?:Z|[+-]\d{2}:\d{2})$/.test(e.startDateTime)) {
      errors.push(
        `"${e.title}": Datum ohne Zeitzonen-Offset "${e.startDateTime}"`,
      );
      continue;
    }
    const parsedDate = new Date(e.startDateTime);
    if (isNaN(parsedDate.getTime())) {
      errors.push(`"${e.title}": ungültiges Datum "${e.startDateTime}"`);
      continue;
    }
    events.push({
      // Kein externalId: dieselbe URL kann mehrere Events liefern (ganzes
      // Programm), ein pro-Seite geteilter externalId würde beim erneuten
      // Einfügen derselben URL zu einem Mehrdeutigkeits-Konflikt in der
      // exakten (source_id, external_id)-Suche in write.ts führen. Erneutes
      // Einfügen läuft stattdessen über den ohnehin vorhandenen
      // Fuzzy-Match (Titel+Venue+Zeit).
      externalId: null,
      title: e.title.trim(),
      description: typeof e.description === "string"
        ? (e.description.trim() || null)
        : null,
      startDateTime: parsedDate.toISOString(),
      endDateTime: null,
      venueName: typeof e.venueName === "string"
        ? (e.venueName.trim() || null)
        : null,
      venueAddress: typeof e.venueAddress === "string"
        ? (e.venueAddress.trim() || null)
        : null,
      url: sourceUrl,
      imageUrl: null,
      priceMin: typeof e.priceMin === "number" ? e.priceMin : null,
      priceMax: typeof e.priceMax === "number" ? e.priceMax : null,
      isFree: typeof e.isFree === "boolean" ? e.isFree : null,
    });
  }

  return { events, errors };
}
