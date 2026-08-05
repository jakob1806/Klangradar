// Interaktive, EINZELNE Bilderrecherche für die Redaktion — Pendant zu
// research-entity-bio/index.ts, nur für Bilder statt Biografien.
// Nutzeranfrage: "das gleiche möchte ich auch bei Bildern haben, man soll
// alle Personen, Venues, Ensembles oder Veranstaltungen auswählen können,
// dann schritt für schritt ein Bild dafür recherchieren von KI lassen. auch
// möglich ist, dass man dann jeweils einen Link dazu schickt... auch soll
// der Admin selber bis zu mehrere Bilder hinzufügen können."
//
// Anders als enrich-entity-images (Cron-Batch, priorisierte Kette,
// needs_review=true für jeden Fremdbild-Fund) ist das hier SYNCHRON,
// EINZELN, vom Admin ausgelöst: erst ein Vorschau-Schritt (mode="search",
// schreibt NICHTS), dann erst nach explizitem Admin-Klick ein Commit-Schritt
// (mode="commit", schreibt über ensureCoverImage in die images-Tabelle) —
// die Redaktion sieht das Bild, bevor es committet wird, daher needsReview
// beim Commit immer false (ein Mensch hat es gerade live geprüft, anders
// als beim automatischen Cron-Fund).
//
// mode="search" ohne sourceUrl: automatische Recherche nach Entitätstyp
// (Wikipedia-Portrait für Personen, Wikimedia Commons für Venues/
// Ensembles, og:image der eigenen/Ticket-Seite für Events).
// mode="search" MIT sourceUrl: extrahiert nur das og:image der angegebenen
// Seite (Nutzerwunsch: "man... schickt einen Link dazu, wo ein Bild sein
// könnte und die KI das Bild heraussucht").
// mode="commit" mit imageBase64: manueller Datei-Upload (Nutzerwunsch:
// "der Admin soll selber bis zu mehrere Bilder hinzufügen können") — ein
// Aufruf pro Datei, der Client ruft es bei mehreren Dateien mehrfach auf.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { extractOgImage } from "../_shared/ogImage.ts";
import { fetchWikipediaPortrait } from "../_shared/wikipediaPortrait.ts";
import { searchCommonsImage } from "../_shared/wikimediaCommons.ts";
import { ensureCoverImage, ensureMagickReady, decodeImage, type ImageOriginType } from "../_shared/imagePipeline.ts";

type EntityType = "person" | "venue" | "ensemble" | "event";

const TABLE_FOR_TYPE: Record<EntityType, string> = {
  person: "persons",
  venue: "venues",
  ensemble: "ensembles",
  event: "events",
};
const NAME_COLUMN_FOR_TYPE: Record<EntityType, string> = {
  person: "full_name",
  venue: "name",
  ensemble: "name",
  event: "title",
};

interface SearchResult {
  found: boolean;
  imageUrl?: string;
  sourcePageUrl?: string;
  sourceName?: string;
  matchReason?: string;
  suggestedLicenseStatus?: "confirmed_free" | "confirmed_licensed";
  error?: string;
}

async function loadEntityName(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entityType: EntityType,
  entityId: string,
): Promise<{ name: string; websiteUrl: string | null; ticketUrl: string | null } | null> {
  const columns = entityType === "event"
    ? "title, website_url, ticket_url"
    : `${NAME_COLUMN_FOR_TYPE[entityType]}, website_url`;
  const { data } = await supabase
    .from(TABLE_FOR_TYPE[entityType])
    .select(columns)
    .eq("id", entityId)
    .maybeSingle();
  if (!data) return null;
  return {
    name: data[NAME_COLUMN_FOR_TYPE[entityType]] as string,
    websiteUrl: (data.website_url as string | undefined) ?? null,
    ticketUrl: (data.ticket_url as string | undefined) ?? null,
  };
}

async function searchForEntity(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entityType: EntityType,
  entityId: string,
  sourceUrlOverride: string | undefined,
): Promise<SearchResult> {
  const entity = await loadEntityName(supabase, entityType, entityId);
  if (!entity) return { found: false, error: "Eintrag nicht gefunden." };

  // Admin hat einen konkreten Link gegeben — nur DIESE Seite auswerten,
  // keine eigenständige Recherche.
  if (sourceUrlOverride) {
    const imageUrl = await extractOgImage(sourceUrlOverride);
    if (!imageUrl) {
      return { found: false, error: "Auf dieser Seite wurde kein verwendbares Bild gefunden." };
    }
    return {
      found: true,
      imageUrl,
      sourcePageUrl: sourceUrlOverride,
      sourceName: new URL(sourceUrlOverride).hostname,
      matchReason: "Manuell angegebener Link",
    };
  }

  switch (entityType) {
    case "person": {
      const portrait = await fetchWikipediaPortrait(entity.name);
      if (!portrait) return { found: false, error: "Kein Wikipedia-Artikel mit Bild gefunden." };
      return {
        found: true,
        imageUrl: portrait.imageUrl,
        sourcePageUrl: portrait.pageUrl,
        sourceName: "Wikipedia",
        matchReason: portrait.description ?? "Wikipedia-Infobox-Bild",
        suggestedLicenseStatus: "confirmed_licensed",
      };
    }
    case "venue":
    case "ensemble": {
      const candidate = await searchCommonsImage(entity.name);
      if (!candidate) return { found: false, error: "Kein passendes Bild auf Wikimedia Commons gefunden." };
      return {
        found: true,
        imageUrl: candidate.url,
        sourcePageUrl: candidate.pageUrl,
        sourceName: "Wikimedia Commons",
        matchReason: `Lizenz: ${candidate.license}${candidate.artist ? ` · ${candidate.artist}` : ""}`,
        suggestedLicenseStatus: "confirmed_free",
      };
    }
    case "event": {
      const pageUrl = entity.websiteUrl ?? entity.ticketUrl;
      if (!pageUrl) return { found: false, error: "Weder Website- noch Ticket-URL hinterlegt." };
      const imageUrl = await extractOgImage(pageUrl);
      if (!imageUrl) return { found: false, error: "Auf der Veranstaltungsseite wurde kein Bild gefunden." };
      return {
        found: true,
        imageUrl,
        sourcePageUrl: pageUrl,
        sourceName: new URL(pageUrl).hostname,
        matchReason: "og:image der Veranstaltungsseite",
      };
    }
  }
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

Deno.serve(async (req) => {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Ungültiger Request-Body" }), { status: 400 });
  }

  const entityType = body.entityType as EntityType | undefined;
  const entityId = body.entityId as string | undefined;
  const mode = body.mode as string | undefined;
  if (!entityType || !TABLE_FOR_TYPE[entityType] || !entityId || !mode) {
    return new Response(JSON.stringify({ error: "entityType, entityId und mode sind erforderlich" }), { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Temporärer Diagnose-Modus für die WORKER_RESOURCE_LIMIT-Untersuchung
  // beim Commit-Pfad — isoliert, ob allein die magick-wasm-Initialisierung
  // (ohne Download/Decode eines echten Bilds) schon das Limit reißt.
  if (mode === "diag") {
    const start = Date.now();
    const steps: Record<string, number> = {};
    try {
      await ensureMagickReady();
      steps.magickReady = Date.now() - start;

      const diagUrl = body.sourceUrl as string | undefined;
      const diagStep = (body.diagStep as string | undefined) ?? "decode";
      if (diagUrl) {
        const res = await fetch(diagUrl);
        steps.fetchHeaders = Date.now() - start;
        if (diagStep === "headers") {
          return new Response(JSON.stringify({ ok: true, steps, status: res.status }));
        }
        const buf = new Uint8Array(await res.arrayBuffer());
        steps.download = Date.now() - start;
        if (diagStep === "download") {
          return new Response(JSON.stringify({ ok: true, steps, bytes: buf.byteLength }));
        }
        const decoded = decodeImage(buf);
        steps.decode = Date.now() - start;
        return new Response(
          JSON.stringify({ ok: true, steps, bytes: buf.byteLength, decoded: decoded ? { w: decoded.width, h: decoded.height } : null }),
        );
      }
      return new Response(JSON.stringify({ ok: true, steps }));
    } catch (err) {
      return new Response(
        JSON.stringify({ ok: false, steps, error: err instanceof Error ? err.message : String(err) }),
        { status: 500 },
      );
    }
  }

  if (mode === "search") {
    const result = await searchForEntity(
      supabase,
      entityType,
      entityId,
      typeof body.sourceUrl === "string" && body.sourceUrl.trim() ? body.sourceUrl.trim() : undefined,
    );
    return new Response(JSON.stringify(result));
  }

  if (mode === "commit") {
    const originType = entityType as ImageOriginType;
    const licenseStatus = (body.licenseStatus as string | undefined) ?? "confirmed_licensed";
    if (!["confirmed_free", "confirmed_licensed"].includes(licenseStatus)) {
      return new Response(
        JSON.stringify({ committed: false, error: "licenseStatus muss confirmed_free oder confirmed_licensed sein." }),
        { status: 400 },
      );
    }

    const imageBase64 = body.imageBase64 as string | undefined;
    const sourceUrl = body.sourceUrl as string | undefined;
    if (!imageBase64 && !sourceUrl) {
      return new Response(JSON.stringify({ committed: false, error: "sourceUrl oder imageBase64 erforderlich" }), { status: 400 });
    }

    const imageId = await ensureCoverImage(supabase, {
      sourceUrl: imageBase64 ? `manual-upload:${crypto.randomUUID()}` : sourceUrl!,
      sourceBytes: imageBase64 ? base64ToBytes(imageBase64) : undefined,
      originType,
      originId: entityId,
      sourcePageUrl: (body.sourcePageUrl as string | undefined) ?? null,
      sourceName: (body.sourceName as string | undefined) ?? (imageBase64 ? "Manueller Upload" : null),
      matchReason: (body.matchReason as string | undefined) ?? null,
      licenseStatus: licenseStatus as "confirmed_free" | "confirmed_licensed",
      // Ein Mensch hat das Bild in DIESEM Request gerade live gesehen und
      // bestätigt (Vorschau-Schritt kam vorher) — anders als beim
      // automatischen Cron-Fund braucht es keine zusätzliche Review-Runde.
      needsReview: false,
    });

    if (!imageId) {
      return new Response(
        JSON.stringify({ committed: false, error: "Bild konnte nicht verarbeitet werden (nicht erreichbar, zu klein, oder ungültiges Format)." }),
        { status: 422 },
      );
    }
    return new Response(JSON.stringify({ committed: true, imageId }));
  }

  return new Response(JSON.stringify({ error: `Unbekannter mode: ${mode}` }), { status: 400 });
});
