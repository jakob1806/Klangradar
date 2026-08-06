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
import { isPublicImageUrl } from "../_shared/imageValidation.ts";
import { USER_AGENT } from "../_shared/robots.ts";

type EntityType = "person" | "venue" | "ensemble" | "event" | "work" | "editorial_collection";

const TABLE_FOR_TYPE: Record<EntityType, string> = {
  person: "persons",
  venue: "venues",
  ensemble: "ensembles",
  event: "events",
  work: "works",
  editorial_collection: "editorial_collections",
};
const NAME_COLUMN_FOR_TYPE: Record<EntityType, string> = {
  person: "full_name",
  venue: "name",
  ensemble: "name",
  event: "title",
  work: "title",
  editorial_collection: "title",
};

interface SearchResult {
  found: boolean;
  imageUrl?: string;
  /** Base64 (ohne "data:...;base64,"-Präfix) einer server-seitig
   * heruntergeladenen Vorschau-Kopie von imageUrl — siehe
   * downloadForPreview(). Der Browser rendert bevorzugt diese Kopie statt
   * imageUrl direkt zu hotlinken, weil viele Quellseiten Hotlinking per
   * Referer-Check blocken (Bild im <img>-Tag lud dann einfach nicht,
   * obwohl die Recherche selbst erfolgreich war — Nutzerfeedback: "Bild
   * aus dem angegebenen Link funktioniert auch nicht"). Rein fürs Preview,
   * der spätere Commit-Schritt lädt weiterhin frisch von imageUrl (siehe
   * ensureCoverImage) — unverändertes, bereits funktionierendes Verhalten.
   */
  imagePreviewBase64?: string;
  imagePreviewMimeType?: string;
  sourcePageUrl?: string;
  sourceName?: string;
  matchReason?: string;
  suggestedLicenseStatus?: "confirmed_free" | "confirmed_licensed";
  error?: string;
}

const PREVIEW_MAX_BYTES = 8_000_000;

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 8192;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

/** Best-effort Server-seitiger Download für die Browser-Vorschau — mit
 * echtem User-Agent statt Browser-Referer, dadurch von vielen
 * Hotlink-Schutz-Regeln nicht betroffen (dieselbe Fetch-Strategie, die
 * checkImageUrl/downloadImage in imagePipeline.ts für den eigentlichen
 * Commit schon nutzen). Gibt null bei jedem Fehler zurück, nie eine
 * Exception — Aufrufer fällt dann auf den direkten Hotlink zurück. */
async function downloadForPreview(url: string): Promise<{ bytes: Uint8Array; mimeType: string } | null> {
  if (!isPublicImageUrl(url)) return null;
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok || !res.body) return null;
    const contentType = res.headers.get("content-type")?.split(";")[0].toLowerCase();
    if (!contentType?.startsWith("image/")) return null;
    const contentLength = res.headers.get("content-length");
    if (contentLength && Number(contentLength) > PREVIEW_MAX_BYTES) {
      await res.body.cancel().catch(() => {});
      return null;
    }
    const buf = new Uint8Array(await res.arrayBuffer());
    if (buf.byteLength > PREVIEW_MAX_BYTES) return null;
    return { bytes: buf, mimeType: contentType };
  } catch {
    return null;
  }
}

// Nicht jede Tabelle hat eine website_url-Spalte (works/editorial_collections
// nicht) — nur für die Typen abfragen, die sie wirklich haben, sonst wirft
// PostgREST einen "column does not exist"-Fehler.
const HAS_WEBSITE_URL: Record<EntityType, boolean> = {
  person: true,
  venue: true,
  ensemble: true,
  event: true,
  work: false,
  editorial_collection: false,
};

async function loadEntityName(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entityType: EntityType,
  entityId: string,
): Promise<{ name: string; websiteUrl: string | null; ticketUrl: string | null } | null> {
  const columns = [
    NAME_COLUMN_FOR_TYPE[entityType],
    ...(HAS_WEBSITE_URL[entityType] ? ["website_url"] : []),
    ...(entityType === "event" ? ["ticket_url"] : []),
  ].join(", ");
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

  const result = await searchWithoutPreview(entity, entityType, sourceUrlOverride);
  if (!result.found || !result.imageUrl) return result;

  // Server-seitig heruntergeladene Vorschau-Kopie ergänzen (siehe
  // downloadForPreview()) — best effort, ein Fehlschlag hier lässt den Fund
  // trotzdem stehen, der Browser zeigt dann nur den direkten Hotlink.
  const preview = await downloadForPreview(result.imageUrl);
  if (preview) {
    result.imagePreviewBase64 = bytesToBase64(preview.bytes);
    result.imagePreviewMimeType = preview.mimeType;
  }
  return result;
}

async function searchWithoutPreview(
  entity: { name: string; websiteUrl: string | null; ticketUrl: string | null },
  entityType: EntityType,
  sourceUrlOverride: string | undefined,
): Promise<SearchResult> {
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
    case "work": {
      // Werke haben oft keinen eigenständigen, exakt betitelten Wikipedia-
      // Artikel (viele Titel sind mehrdeutig/uneindeutig) — Wikipedia zuerst
      // (funktioniert gut für bekannte Einzelwerke mit eigenem Artikel,
      // z. B. Opern/Oratorien), sonst Commons-Volltextsuche als breiterer
      // Fallback (Aufführungsfotos, Partitur-/Notenblatt-Scans, Plakate).
      const portrait = await fetchWikipediaPortrait(entity.name);
      if (portrait) {
        return {
          found: true,
          imageUrl: portrait.imageUrl,
          sourcePageUrl: portrait.pageUrl,
          sourceName: "Wikipedia",
          matchReason: portrait.description ?? "Wikipedia-Infobox-Bild",
          suggestedLicenseStatus: "confirmed_licensed",
        };
      }
      const candidate = await searchCommonsImage(entity.name);
      if (!candidate) {
        return { found: false, error: "Kein passendes Bild auf Wikipedia/Wikimedia Commons gefunden." };
      }
      return {
        found: true,
        imageUrl: candidate.url,
        sourcePageUrl: candidate.pageUrl,
        sourceName: "Wikimedia Commons",
        matchReason: `Lizenz: ${candidate.license}${candidate.artist ? ` · ${candidate.artist}` : ""}`,
        suggestedLicenseStatus: "confirmed_free",
      };
    }
    case "editorial_collection": {
      // Eine redaktionelle Sammlung ("Höhepunkte der Woche") ist kein
      // öffentlich bekanntes, recherchierbares Objekt — keine automatische
      // KI-Suche, nur Link (sourceUrlOverride, siehe oben) oder Upload.
      return { found: false, error: "Kein automatischer Bildvorschlag für Sammlungen — Link angeben oder Datei hochladen." };
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

    // editorial_collections.cover_image_url ist (anders als bei Personen/
    // Venues/Ensembles/Events, die über die images-Tabelle/entityGallery
    // in der App gelesen werden) noch eine direkte URL-Spalte — dieselbe
    // öffentliche Storage-URL hier zusätzlich zurückschreiben, statt die
    // Flutter-Seite zusätzlich umzustellen (Nutzerwunsch war nur: Titelbild
    // soll über dieselbe recherchierte/hochgeladene Pipeline laufen statt
    // eines von Hand eingetippten Links).
    if (entityType === "editorial_collection") {
      const { data: image } = await supabase.from("images").select("storage_path").eq("id", imageId).maybeSingle();
      if (image?.storage_path) {
        const { data: publicUrlData } = supabase.storage.from("ingested-images").getPublicUrl(image.storage_path);
        await supabase.from("editorial_collections").update({ cover_image_url: publicUrlData.publicUrl }).eq("id", entityId);
      }
    }

    return new Response(JSON.stringify({ committed: true, imageId }));
  }

  return new Response(JSON.stringify({ error: `Unbekannter mode: ${mode}` }), { status: 400 });
});
