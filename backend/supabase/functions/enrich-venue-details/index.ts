// Reichert Venue-Profile automatisiert an — Teil der grundlegend
// überarbeiteten Datenanreicherung (Nutzeranfrage Abschnitt 2: "Baue
// reichhaltige Venueprofile"). Holt den Volltext der eigenen offiziellen
// Website (_shared/pageText.ts) und extrahiert daraus strukturiert
// Geschichte/künstlerisches Profil, Stadtteil, Telefon/E-Mail, Anreise
// (Fahrrad/Taxi/Fußweg — ÖPNV/Parken existieren bereits als mvv_stops/
// parking_info_de), Einlass-/Garderoben-/Sicherheitshinweise,
// gastronomische Hinweise, Entitätsart und zusätzliche
// Barrierefreiheits-Details (ergänzt das bestehende accessibility-JSONB).
//
// Gleiches Grundmuster wie enrich-event-references: nur die eigene
// offizielle Website als Quelle (kein Fremdbild-Risiko, siehe
// enrich-entity-images für die Bild-Variante desselben Prinzips), jedes
// Feld nur befüllen wenn aktuell leer (nie eine bestehende, ggf.
// redaktionell gepflegte Angabe überschreiben), Provenienz pro Feld via
// _shared/provenance.ts, konservative Extraktion ("nicht erfinden").
//
// Aufruf: POST { limit?: number } — verarbeitet bis zu `limit` (Default 5,
// klein gehalten wegen des Seitenabrufs pro Venue, siehe
// WORKER_RESOURCE_LIMIT-Erfahrung bei enrich-event-references) Venues mit
// fehlendem history_de.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { fetchPageText } from "../_shared/pageText.ts";
import { recordFieldSources } from "../_shared/provenance.ts";

const DEFAULT_LIMIT = 5;

const VENUE_TYPE_OPTIONS = [
  "konzertsaal",
  "kirche",
  "theater",
  "museum",
  "schloss",
  "kulturzentrum",
  "sonstiges",
];

const ENRICH_FUNCTION: AiFunctionDeclaration = {
  name: "extract_venue_profile",
  description: "Aus dem Volltext der offiziellen Venue-Website erkannte strukturierte Profildaten.",
  parameters: {
    type: "object",
    properties: {
      historyDe: {
        type: "string",
        description:
          "Geschichte und künstlerisches Profil der Venue auf Deutsch (2-5 Sätze), NUR aus tatsächlich im " +
          "Text stehenden Informationen — keine erfundenen Details, keine Floskeln. Weglassen, wenn der Text " +
          "dafür nicht genug hergibt.",
      },
      venueType: {
        type: "string",
        enum: VENUE_TYPE_OPTIONS,
        description: "Art der Spielstätte, nur wenn eindeutig aus dem Text/Kontext erkennbar.",
      },
      district: {
        type: "string",
        description: "Münchner Stadtteil NUR, wenn im Text explizit genannt (z. B. 'Maxvorstadt'), sonst weglassen.",
      },
      phone: {
        type: "string",
        description: "Telefonnummer NUR, wenn wortwörtlich im Text steht, sonst weglassen.",
      },
      email: {
        type: "string",
        description: "E-Mail-Adresse NUR, wenn wortwörtlich im Text steht, sonst weglassen.",
      },
      arrivalInfo: {
        type: "string",
        description:
          "Hinweise zur Anreise mit Fahrrad, Taxi oder zu Fuß NUR, wenn im Text explizit genannt — NICHT " +
          "ÖPNV/Parken erwähnen (dafür gibt es bereits eigene Felder), nur Fahrrad/Taxi/Fußweg-spezifische " +
          "Hinweise. Weglassen, wenn nichts dergleichen im Text steht.",
      },
      doorsInfo: {
        type: "string",
        description:
          "Einlass-, Garderoben- oder Sicherheitshinweise NUR, wenn im Text explizit genannt (z. B. " +
          "'Garderobe kostenlos', 'Taschenkontrolle am Einlass'), sonst weglassen.",
      },
      cateringInfo: {
        type: "string",
        description: "Gastronomische Hinweise (Foyer-Bar, Restaurant) NUR, wenn im Text explizit genannt, sonst weglassen.",
      },
      stepFreeAccess: {
        type: "boolean",
        description: "true/false NUR, wenn im Text explizit ein stufenloser Zugang erwähnt oder verneint wird, sonst weglassen.",
      },
      elevator: {
        type: "boolean",
        description: "true/false NUR, wenn im Text explizit ein Aufzug erwähnt oder dessen Fehlen genannt wird, sonst weglassen.",
      },
      accessibleToilet: {
        type: "boolean",
        description: "true/false NUR, wenn im Text explizit ein barrierefreies WC erwähnt oder verneint wird, sonst weglassen.",
      },
    },
    required: [],
  },
};

interface VenueRow {
  id: string;
  name: string;
  website_url: string | null;
  history_de: string | null;
  district: string | null;
  phone: string | null;
  email: string | null;
  venue_type: string | null;
  arrival_info_de: string | null;
  doors_info_de: string | null;
  catering_info_de: string | null;
  accessibility: Record<string, unknown> | null;
  profile_checked_at: string | null;
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

  const { data: venues, error: fetchError } = await supabase
    .from("venues")
    .select(
      "id, name, website_url, history_de, district, phone, email, venue_type, arrival_info_de, doors_info_de, catering_info_de, accessibility, profile_checked_at",
    )
    .is("profile_checked_at", null)
    .not("website_url", "is", null)
    .limit(limit)
    .returns<VenueRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!venues || venues.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine Venues mit fehlendem Profil übrig." }));
  }

  let updated = 0;
  const errors: string[] = [];

  for (const venue of venues) {
    try {
      const pageText = await fetchPageText(venue.website_url!);
      if (!pageText) {
        // Bug (live beim Backfill entdeckt): ungeprüftes "continue" ohne
        // profile_checked_at zu setzen führte dazu, dass Venues mit
        // dauerhaft nicht abrufbarem Seitentext (robots.txt-Sperre, tote
        // Seite) bei JEDEM Lauf erneut ausgewählt wurden und der Backfill
        // nie konvergierte. profile_checked_at trotzdem setzen — ein
        // erneuter Versuch ist über einen gezielten Admin-Reset möglich,
        // aber nicht per Dauerschleife alle 10 Minuten.
        await supabase.from("venues").update({ profile_checked_at: new Date().toISOString() }).eq("id", venue.id);
        continue;
      }

      const response = await callAiFunction(
        "Du extrahierst strukturierte Profildaten einer Münchner Konzert-/Veranstaltungsspielstätte aus dem " +
          "Volltext ihrer offiziellen Website. Sei konservativ: lieber ein leeres Feld als geraten. Erfinde " +
          "NIEMALS Informationen, die nicht wortwörtlich im Text stehen.",
        `Venue: ${venue.name}\n\nVolltext der offiziellen Website:\n${pageText}`,
        ENRICH_FUNCTION,
      );
      const args = response?.args;
      if (!args) {
        errors.push(`"${venue.name}": AI-Aufruf fehlgeschlagen (alle Provider)`);
        continue;
      }

      const patch: Record<string, unknown> = {};
      const provenanceFields: string[] = [];

      if (!venue.history_de && typeof args.historyDe === "string" && args.historyDe.trim()) {
        patch.history_de = args.historyDe.trim();
        provenanceFields.push("history_de");
      }
      if (!venue.venue_type && typeof args.venueType === "string" && VENUE_TYPE_OPTIONS.includes(args.venueType)) {
        patch.venue_type = args.venueType;
        provenanceFields.push("venue_type");
      }
      if (!venue.district && typeof args.district === "string" && args.district.trim()) {
        patch.district = args.district.trim();
        provenanceFields.push("district");
      }
      if (!venue.phone && typeof args.phone === "string" && args.phone.trim()) {
        patch.phone = args.phone.trim();
        provenanceFields.push("phone");
      }
      if (!venue.email && typeof args.email === "string" && args.email.trim()) {
        patch.email = args.email.trim();
        provenanceFields.push("email");
      }
      if (!venue.arrival_info_de && typeof args.arrivalInfo === "string" && args.arrivalInfo.trim()) {
        patch.arrival_info_de = args.arrivalInfo.trim();
        provenanceFields.push("arrival_info_de");
      }
      if (!venue.doors_info_de && typeof args.doorsInfo === "string" && args.doorsInfo.trim()) {
        patch.doors_info_de = args.doorsInfo.trim();
        provenanceFields.push("doors_info_de");
      }
      if (!venue.catering_info_de && typeof args.cateringInfo === "string" && args.cateringInfo.trim()) {
        patch.catering_info_de = args.cateringInfo.trim();
        provenanceFields.push("catering_info_de");
      }

      // accessibility ist ein JSONB-Objekt — nur die NEU erkannten Keys
      // hinzufügen, bestehende Keys (z. B. wheelchair, schon vom
      // Excel-Import gesetzt) unangetastet lassen.
      const accessibilityPatch: Record<string, boolean> = {};
      if (typeof args.stepFreeAccess === "boolean" && venue.accessibility?.step_free === undefined) {
        accessibilityPatch.step_free = args.stepFreeAccess;
      }
      if (typeof args.elevator === "boolean" && venue.accessibility?.elevator === undefined) {
        accessibilityPatch.elevator = args.elevator;
      }
      if (typeof args.accessibleToilet === "boolean" && venue.accessibility?.accessible_toilet === undefined) {
        accessibilityPatch.accessible_toilet = args.accessibleToilet;
      }
      if (Object.keys(accessibilityPatch).length > 0) {
        patch.accessibility = { ...(venue.accessibility ?? {}), ...accessibilityPatch };
        provenanceFields.push("accessibility");
      }

      // profile_checked_at wird unabhängig davon gesetzt, ob die Website
      // etwas Neues hergab — sonst würden Venues ohne extrahierbare Daten
      // (z. B. keine Geschichte auf der Seite) bei JEDEM Lauf erneut
      // ausgewählt und der Backfill käme nie zum Ende (live beobachtet:
      // 11 Batches à 5 Venues brachten nur 1 Venue voran). Gleiches Prinzip
      // wie references_checked_at bei enrich-event-references.
      const checkedPatch = { ...patch, profile_checked_at: new Date().toISOString() };

      const { error: updateError } = await supabase.from("venues").update(checkedPatch).eq("id", venue.id);
      if (updateError) {
        errors.push(`"${venue.name}": Update fehlgeschlagen — ${updateError.message}`);
        continue;
      }
      if (Object.keys(patch).length > 0) {
        updated++;
        await recordFieldSources(
          supabase,
          provenanceFields.map((fieldName) => ({
            entityType: "venue" as const,
            entityId: venue.id,
            fieldName,
            sourceUrl: venue.website_url,
            sourceName: "Offizielle Venue-Website (via enrich-venue-details)",
            confidence: "likely" as const,
          })),
        );
      }
    } catch (err) {
      errors.push(`"${venue.name}": ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      processed: venues.length,
      updated,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
