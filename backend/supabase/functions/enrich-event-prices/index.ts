// Reichert Events ohne Preisangabe automatisiert an — Nutzeranfrage: "alle
// events zeigen nach wie vor 'preis auf anfrage' statt einer preisspanne".
// Root Cause: die Bulk-Ingestion-Parser (ingest-source/parsers/*) übernehmen
// nur, was Schema.org/iCal/RSS/Scrape strukturiert mitliefern — anders als
// der manuelle "Von URL hinzufügen"-Import (extract-event-from-url), der
// bereits einen KI-Fallback für Preise hat. Diese Funktion schließt genau
// diese Lücke für die Masse der Bulk-importierten Events, nach demselben
// Grundmuster wie enrich-venue-details: eigene Ticket-/Website-Seite als
// einzige Quelle, Feld nur befüllen wenn aktuell leer, Provenienz pro Feld,
// konservative Extraktion ("nicht erfinden"), price_checked_at verhindert
// endlose Wiederholung für Events ohne extrahierbaren Preis.
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 5,
// klein gehalten wegen des Seitenabrufs pro Event) Events mit fehlendem
// Preis.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchPageText } from "../_shared/pageText.ts";
import { recordFieldSources } from "../_shared/provenance.ts";

const DEFAULT_LIMIT = 5;

const PRICE_EXTRACTION_FUNCTION: AiFunctionDeclaration = {
  name: "extract_event_price",
  description: "Aus dem Volltext einer Ticket-/Veranstaltungsseite erkannte Preisangaben.",
  parameters: {
    type: "object",
    properties: {
      isFree: {
        type: "boolean",
        description: "true NUR, wenn der Text den Eintritt explizit als kostenlos/frei bezeichnet.",
      },
      priceMin: {
        type: "number",
        description: "Günstigster genannter Ticketpreis in Euro, NUR wenn wortwörtlich im Text erkennbar.",
      },
      priceMax: {
        type: "number",
        description:
          "Teuerster genannter Ticketpreis in Euro, NUR wenn im Text mehrere Preiskategorien erkennbar sind. " +
          "Weglassen, wenn nur ein einzelner Preis genannt wird.",
      },
    },
    required: [],
  },
};

interface EventRow {
  id: string;
  title: string;
  ticket_url: string | null;
  website_url: string | null;
  price_min: number | null;
  price_max: number | null;
  is_free: boolean | null;
}

Deno.serve(async (req) => {
  if (!hasAnyAiProviderConfigured()) {
    return new Response(
      JSON.stringify({ error: "Kein AI-Provider-Secret gesetzt (CEREBRAS_API_KEY, NVIDIA_API_KEY oder GEMINI_API_KEY)" }),
      { status: 500 },
    );
  }

  let body: { limit?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const limit = typeof body.limit === "number" && body.limit > 0 ? Math.min(body.limit, 20) : DEFAULT_LIMIT;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: events, error: fetchError } = await supabase
    .from("events")
    .select("id, title, ticket_url, website_url, price_min, price_max, is_free")
    .is("price_checked_at", null)
    .eq("is_free", false)
    .in("status", ["scheduled", "draft"])
    .gte("start_datetime", new Date().toISOString())
    .or("ticket_url.not.is.null,website_url.not.is.null")
    .limit(limit)
    .returns<EventRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!events || events.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine Events mit fehlendem Preis übrig." }));
  }

  let updated = 0;
  const errors: string[] = [];

  for (const event of events) {
    const pageUrl = event.ticket_url ?? event.website_url;
    try {
      const pageText = pageUrl ? await fetchPageText(pageUrl) : null;
      if (!pageText) {
        // Wie bei enrich-venue-details: price_checked_at trotzdem setzen,
        // sonst wird dasselbe nicht abrufbare Event bei jedem Lauf erneut
        // ausgewählt und der Backfill kommt nie zum Ende.
        await supabase.from("events").update({ price_checked_at: new Date().toISOString() }).eq("id", event.id);
        continue;
      }

      const response = await callAiFunction(
        "Du extrahierst Ticketpreise einer klassischen Konzert-/Veranstaltungsseite aus dem Volltext. Sei " +
          "konservativ: lieber kein Preis als geraten. Erfinde NIEMALS einen Preis, der nicht wortwörtlich im " +
          "Text steht.",
        `Veranstaltung: ${event.title}\n\nVolltext der Ticket-/Veranstaltungsseite:\n${pageText}`,
        PRICE_EXTRACTION_FUNCTION,
      );
      const args = response?.args;
      if (!args) {
        errors.push(`"${event.title}": AI-Aufruf fehlgeschlagen (alle Provider)`);
        await supabase.from("events").update({ price_checked_at: new Date().toISOString() }).eq("id", event.id);
        continue;
      }

      const patch: Record<string, unknown> = {};
      const provenanceFields: string[] = [];

      if (args.isFree === true) {
        patch.is_free = true;
        provenanceFields.push("is_free");
      } else {
        if (typeof args.priceMin === "number" && args.priceMin >= 0) {
          patch.price_min = args.priceMin;
          provenanceFields.push("price_min");
        }
        if (typeof args.priceMax === "number" && args.priceMax >= 0) {
          patch.price_max = args.priceMax;
          provenanceFields.push("price_max");
        }
      }

      const checkedPatch = { ...patch, price_checked_at: new Date().toISOString() };
      const { error: updateError } = await supabase.from("events").update(checkedPatch).eq("id", event.id);
      if (updateError) {
        errors.push(`"${event.title}": Update fehlgeschlagen — ${updateError.message}`);
        continue;
      }
      if (Object.keys(patch).length > 0) {
        updated++;
        await recordFieldSources(
          supabase,
          provenanceFields.map((fieldName) => ({
            entityType: "event" as const,
            entityId: event.id,
            fieldName,
            sourceUrl: pageUrl,
            sourceName: "Ticket-/Veranstaltungsseite (via enrich-event-prices)",
            confidence: "likely" as const,
          })),
        );
      }
    } catch (err) {
      errors.push(`"${event.title}": ${err instanceof Error ? err.message : String(err)}`);
      await supabase.from("events").update({ price_checked_at: new Date().toISOString() }).eq("id", event.id);
    }
  }

  return new Response(
    JSON.stringify({
      processed: events.length,
      updated,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
