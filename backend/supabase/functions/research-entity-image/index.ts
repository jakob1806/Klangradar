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
// mode="search" ohne sourceUrl: automatische Recherche nach Entitätstyp.
// Erster Schritt ist bei Personen/Venues/Ensembles/Werken/Events (ohne
// eigenes og:image) eine breite Websuche über das GANZE offene Web statt
// nur kuratierter Wikimedia-Quellen (Nutzerfeedback: "wikipedia commons
// ist so ungenau und hat oft keine bilder") — zuerst über DuckDuckGos
// HTML-Suche (searchImageViaWebSearch, kein Account/API-Key nötig, siehe
// _shared/duckDuckGoSearch.ts), optional ergänzt um Geminis "Grounding
// with Google Search" (GEMINI_IMAGE_SEARCH_API_KEY), falls gesetzt UND
// DuckDuckGo nichts liefert — auf Nutzerwunsch bewusst NICHT die primäre
// Quelle, da sie ein (kontingentiertes) Google-Konto voraussetzt, während
// DuckDuckGo ohne Anmeldung auskommt. Findet keine der beiden Websuchen
// etwas, fällt die Kette auf die bisherigen, engeren Quellen zurück:
// Wikipedia-Portrait/Wikimedia Commons/Wikidata für Personen/Venues/
// Ensembles/Werke, og:image der eigenen/Ticket-Seite bzw. das Venue-Foto
// für Events.
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
import { searchWikidataImage } from "../_shared/wikidataImage.ts";
import { searchViaGeminiGrounding } from "../_shared/geminiGroundedSearch.ts";
import { searchDuckDuckGo } from "../_shared/duckDuckGoSearch.ts";
import { searchOfficialSiteForImages } from "../_shared/officialSiteImageSearch.ts";
import { type ImageSourceAttempt, type RaceImageSourcesResult, raceImageSources } from "../_shared/raceImageSources.ts";
import {
  ensureCoverImageWithReason,
  ensureMagickReady,
  decodeImage,
  type CoverImageFailureReason,
  type ImageOriginType,
} from "../_shared/imagePipeline.ts";

// Nutzerfeedback: der manuelle Datei-Upload scheiterte bisher immer mit
// derselben pauschalen Meldung ("nicht erreichbar, zu klein, oder
// ungültiges Format"), egal welcher der vier Gründe tatsächlich zutraf —
// jetzt eine passende Meldung je nach von ensureCoverImageWithReason()
// zurückgegebenem Grund. "unreachable"/"download_failed" bleiben trotzdem
// im Text erwähnt für den (hier seltenen) Fall, dass commit doch mit einer
// sourceUrl statt imageBase64 aufgerufen wird.
function commitFailureMessage(reason: CoverImageFailureReason | undefined): string {
  switch (reason) {
    case "decode_failed":
      return "Die Datei konnte nicht als Bild gelesen werden — vermutlich beschädigt oder ein nicht unterstütztes Format (unterstützt: JPEG, PNG, WebP).";
    case "too_small":
      return "Bild zu klein — mindestens 640×480px nötig, sonst wirkt es in der App später hochskaliert unscharf.";
    case "bad_aspect_ratio":
      return "Ungewöhnliches Seitenverhältnis (nicht zwischen 2:5 und 3:1) — vermutlich kein normales Foto, sondern z. B. ein Banner oder eine Sidebar-Grafik.";
    case "too_blurry":
      return "Das Bild ist zu unscharf/verpixelt für eine gute Darstellung — bitte ein schärferes Bild suchen.";
    case "unreachable":
      return "Die Bild-URL war nicht erreichbar.";
    case "download_failed":
      return "Der Download der Bilddatei ist fehlgeschlagen.";
    case "storage_error":
      return "Das Bild konnte nicht gespeichert werden (Storage-/Datenbankfehler) — bitte erneut versuchen.";
    default:
      return "Bild konnte nicht verarbeitet werden.";
  }
}
import { checkImageUrl, isPublicImageUrl } from "../_shared/imageValidation.ts";
import { USER_AGENT } from "../_shared/robots.ts";
import { logSystemAction } from "../_shared/systemLog.ts";

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

/** Ein Eintrag der Recherche-Protokollierung für system_logs (Nutzerwunsch,
 * Abschnitt 10: "pro Suchlauf Quellen, aufgerufene URLs, gefundene/
 * abgelehnte Kandidaten, Fehler, Laufzeit, Endstatus speichern"). Reuse der
 * bestehenden generischen system_logs-Tabelle statt einer neuen
 * ingestion_runs-artigen Struktur — dieselbe Tabelle wird schon für
 * automatisierte Fuzzy-Matches/Merges genutzt (siehe logSystemAction). */
interface RunLogEntry {
  source: string;
  outcome: "found" | "not_found" | "error" | "skipped";
  detail?: string;
}

/** Verarbeitungsreihenfolge Schritt 1 (Nutzervorgabe): existiert für DIESE
 * Entität schon ein redaktionell bestätigtes Bild (review_status=approved),
 * wird es direkt wiederverwendet — keine erneute Websuche. Das eigentliche
 * "für alle künftigen Events automatisch vorschlagen" passiert schon
 * strukturell dadurch, dass Bilder pro (origin_type, origin_id) = pro
 * Person/Ensemble/Venue gespeichert werden, nicht pro Event — die
 * bestehende Galerie-Anzeige (entity_gallery_providers.dart) liest darüber
 * jetzt schon automatisch für jedes Vorkommen derselben Entität. Diese
 * Prüfung hier verhindert zusätzlich, dass ein Admin-Klick auf "Bild
 * recherchieren" für eine Entität mit längst bestätigtem Bild unnötig eine
 * komplette Web-Recherche auslöst. */
async function findExistingConfirmedImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  originType: EntityType,
  originId: string,
): Promise<SearchResult | null> {
  const { data } = await supabase
    .from("images")
    .select("storage_path, source_url, source_name, source_page_url")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .eq("review_status", "approved")
    .not("storage_path", "is", null)
    .order("is_primary", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data) return null;

  const imageUrl = data.storage_path
    ? supabase.storage.from("ingested-images").getPublicUrl(data.storage_path).data.publicUrl
    : data.source_url;
  if (!imageUrl) return null;

  return {
    found: true,
    imageUrl,
    sourcePageUrl: data.source_page_url ?? undefined,
    sourceName: data.source_name ?? "Zentrale Bilddatenbank",
    matchReason: "Bereits bestätigtes Bild aus der zentralen Bilddatenbank — keine erneute Websuche nötig.",
  };
}

/** Schritt 3 der Verarbeitungsreihenfolge (Nutzervorgabe): offizielle
 * Website der Entität crawlen (officialSiteImageSearch.ts) und den
 * bestbewerteten Kandidaten vorschlagen, falls einer gefunden wurde — auch
 * bei "low"-Konfidenz, da dieser Endpunkt ohnehin IMMER einen expliziten
 * Admin-Bestätigungsschritt vor dem Commit hat (siehe Datei-Kommentar oben),
 * eine niedrige Konfidenz also nur die Formulierung des matchReason
 * beeinflusst, nicht ob überhaupt vorgeschlagen wird. */
/** Liefert zusätzlich zum SearchResult den 0–10-Score des Top-Kandidaten
 * (aus officialSiteImageSearch.ts's eigenem Scoring) — für den Tier-Score-
 * Vergleich innerhalb einer Vertrauens-Tier in raceImageSources(). Loggt
 * NICHT mehr selbst (anders als früher): searchWithoutPreview() protokolliert
 * jetzt einheitlich über die attempts-Liste des Rennens, damit paralleles
 * und sequenzielles Logging nicht durcheinandergeraten. crawl.errors (es
 * kann mehrere pro Crawl geben, nicht nur einen) werden trotzdem sofort
 * geloggt, weil raceImageSources() dafür keinen eigenen Slot hat. */
async function searchOfficialSite(
  entityName: string,
  websiteUrl: string,
  sourceLabel: string,
  log: (entry: RunLogEntry) => void,
): Promise<{ result: SearchResult; score: number } | null> {
  const crawl = await searchOfficialSiteForImages(entityName, websiteUrl);
  for (const err of crawl.errors) {
    log({ source: `${sourceLabel} (offizielle Website)`, outcome: "error", detail: err });
  }
  const top = crawl.candidates[0];
  if (!top) return null;
  const confidenceLabel = top.confidence === "high" ? "hohe" : top.confidence === "medium" ? "mittlere" : "geringe";
  return {
    score: top.score,
    result: {
      found: true,
      imageUrl: top.url,
      sourcePageUrl: top.pageUrl,
      sourceName: new URL(top.pageUrl).hostname,
      matchReason: `${sourceLabel} — offizielle Website (${confidenceLabel} Treffersicherheit)${top.reasons[0] ? `: ${top.reasons[0]}` : ""}`,
      suggestedLicenseStatus: "confirmed_licensed",
    },
  };
}

/** Testfall 12 (Nutzervorgabe): "ein Bild wird abgelehnt und darf nicht
 * automatisch erneut vorgeschlagen werden" — dieselbe Quelle (z.B.
 * Wikipedia-Infobox) liefert bei einer erneuten Recherche oft wieder
 * exakt dieselbe URL, die eine Redakteurin zuvor schon bewusst abgelehnt
 * hat. ensureCoverImage()s eigene Dedupe-Stufen wehren das beim COMMIT
 * bereits ab (siehe imagePipeline.ts), aber ohne diese Prüfung würde der
 * SUCHSCHRITT das abgelehnte Bild trotzdem wieder als "gefunden" in der
 * Vorschau anzeigen, bevor es überhaupt zum Commit kommt. */
async function isRejectedImageUrl(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  originType: EntityType,
  originId: string,
  url: string,
): Promise<boolean> {
  const { data } = await supabase
    .from("images")
    .select("id")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .eq("source_url", url)
    .eq("review_status", "rejected")
    .limit(1)
    .maybeSingle();
  return !!data;
}

// Nutzerwunsch: "'Kein Bild gefunden' als eigenen Zustand führen, getrennt
// von 'noch nie gesucht'" — enrich-entity-images (Batch-Cron) schreibt das
// schon bei jedem Fehlschlag, dieser interaktive Einzelsuch-Pfad bisher
// nicht. Nur für die drei Typen, die media/page.tsx tatsächlich als
// eigene Statistik-Karte zeigt UND die beide Spalten überhaupt besitzen
// (20260906000001_image_search_reason_tracking.sql +
// 20261015000001_fast_person_biographies_and_image_queue.sql) — events
// haben nur last_image_search_note, works/editorial_collections keins
// von beiden.
const HAS_IMAGE_SEARCH_TRACKING: Partial<Record<EntityType, boolean>> = {
  person: true,
  venue: true,
  ensemble: true,
};

async function markSearchedWithoutResult(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entityType: EntityType,
  entityId: string,
  note: string,
): Promise<void> {
  if (!HAS_IMAGE_SEARCH_TRACKING[entityType]) return;
  await supabase
    .from(TABLE_FOR_TYPE[entityType])
    .update({ image_search_checked_at: new Date().toISOString(), last_image_search_note: note })
    .eq("id", entityId)
    .catch(() => {});
}

async function searchForEntity(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entityType: EntityType,
  entityId: string,
  sourceUrlOverride: string | undefined,
): Promise<SearchResult> {
  const startedAt = Date.now();
  const runLog: RunLogEntry[] = [];
  const entity = await loadEntityName(supabase, entityType, entityId);
  if (!entity) return { found: false, error: "Eintrag nicht gefunden." };

  let result = await searchWithoutPreview(supabase, entity, entityType, entityId, sourceUrlOverride, runLog);

  if (result.found && result.imageUrl) {
    const alreadyRejected = await isRejectedImageUrl(supabase, entityType, entityId, result.imageUrl).catch(() => false);
    if (alreadyRejected) {
      runLog.push({
        source: "Ablehnungs-Prüfung",
        outcome: "error",
        detail: "Gefundener Kandidat wurde für diese Entität bereits abgelehnt — wird nicht erneut vorgeschlagen.",
      });
      result = {
        found: false,
        error: "Das automatisch gefundene Bild wurde für diese Entität bereits abgelehnt. Bitte einen anderen Link angeben oder eine Datei hochladen.",
      };
    }
  }

  // Best-effort — ein Logging-Fehler darf die eigentliche Recherche nie
  // scheitern lassen (gleiches Prinzip wie logSystemAction selbst).
  await logSystemAction(
    supabase,
    entityType,
    entityId,
    "image_search",
    {
      manualSourceUrl: sourceUrlOverride ?? null,
      steps: runLog,
      finalStatus: result.found ? "found" : "not_found",
      error: result.found ? null : result.error ?? null,
      runtimeMs: Date.now() - startedAt,
    },
    "admin_image_research",
  ).catch(() => {});

  if (!result.found || !result.imageUrl) {
    await markSearchedWithoutResult(supabase, entityType, entityId, result.error ?? "Kein Bild gefunden.");
    return result;
  }

  // Server-seitig heruntergeladene Vorschau-Kopie ergänzen (siehe
  // downloadForPreview()) — best effort, ein Fehlschlag hier lässt den Fund
  // trotzdem stehen, der Browser zeigt dann nur den direkten Hotlink.
  const preview = await downloadForPreview(result.imageUrl);
  if (preview) {
    // Live beobachtet: ein Venue-Foto mit nur 225×225px (11,5 KB) wurde als
    // "gefunden" angezeigt (im Browser hochskaliert, sah brauchbar aus),
    // scheiterte dann aber beim Übernehmen an der 640×480-Mindestauflösung
    // der Bildpipeline (ensureCoverImage/isAcceptableImageDimensions) —
    // verwirrender Fehlschlag NACH der Vorschau statt vorher erkannt.
    // Echte Dimensionen ohne vollen ImageMagick-Decode zu ermitteln würde
    // dieselbe teure Initialisierung schon im Suchschritt fällig machen
    // (siehe die frühere WORKER_RESOURCE_LIMIT-Untersuchung) — als
    // günstiger Kompromiss: eine derart kleine Datei ist praktisch nie ein
    // Foto ≥640×480 (selbst stark komprimiertes JPEG dieser Größe liegt
    // deutlich über diesem Schwellenwert), daher schon hier als "nicht
    // gefunden" behandeln statt einen zum Scheitern verurteilten Fund zu
    // zeigen.
    const MIN_PLAUSIBLE_PHOTO_BYTES = 20_000;
    if (preview.bytes.byteLength < MIN_PLAUSIBLE_PHOTO_BYTES) {
      const error = `Gefundenes Bild ist zu klein (nur ${Math.round(preview.bytes.byteLength / 1024)} KB) — vermutlich ein Thumbnail unter der Mindestauflösung.`;
      await markSearchedWithoutResult(supabase, entityType, entityId, error);
      return { found: false, error };
    }
    result.imagePreviewBase64 = bytesToBase64(preview.bytes);
    result.imagePreviewMimeType = preview.mimeType;
  }
  return result;
}

/** Letzter Rückfall für Events ohne eigenes og:image: das (bereits
 * freigegebene) Foto des Veranstaltungsorts, klar als solches markiert.
 * null, wenn das Event keinen Venue hat oder der Venue selbst kein Foto. */
async function venuePhotoFallback(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  eventId: string,
): Promise<SearchResult | null> {
  const { data: event } = await supabase.from("events").select("venue_id").eq("id", eventId).maybeSingle();
  if (!event?.venue_id) return null;
  const { data: venue } = await supabase.from("venues").select("name, photo_url").eq("id", event.venue_id)
    .maybeSingle();
  if (!venue?.photo_url) return null;
  return {
    found: true,
    imageUrl: venue.photo_url,
    sourceName: `Foto des Veranstaltungsorts (${venue.name})`,
    matchReason: "Kein eigenes Bild gefunden — Rückfall auf das Venue-Foto.",
    suggestedLicenseStatus: "confirmed_licensed",
  };
}

/** Venue-Name für eine bessere Websuche-Anfrage bei Events — null bei
 * jedem Fehler/fehlendem Venue, dann läuft die Suche nur mit dem
 * Event-Titel. */
// Klein (aktuell 5 Städte) und ändert sich pro Isolate-Lebensdauer praktisch
// nie — gleicher Cache-Ansatz wie in enrich-entity-images/index.ts, spart
// eine wiederholte regions-Abfrage über mehrere Suchen hinweg.
const cityNameCache = new Map<string, string | null>();

async function resolveCityName(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  cityId: string | null | undefined,
): Promise<string | undefined> {
  if (!cityId) return undefined;
  if (cityNameCache.has(cityId)) return cityNameCache.get(cityId) ?? undefined;
  const { data } = await supabase.from("regions").select("name").eq("id", cityId).maybeSingle();
  const name = (data?.name as string | undefined) ?? null;
  cityNameCache.set(cityId, name);
  return name ?? undefined;
}

/** Bug-Fund: die Venue/Ensemble/Event-Bildsuche nutzte bisher überall fest
 * "München" als Suchkontext, unabhängig von der tatsächlichen Stadt der
 * Venue — seit der Multi-City-Erweiterung dadurch für Berlin/Hamburg/Wien/
 * Frankfurt falsch statt nur ungenau. Löst die echte Stadt über venues.city_id
 * auf. */
async function resolveVenueCityName(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  venueId: string,
): Promise<string | undefined> {
  const { data: venue } = await supabase.from("venues").select("city_id").eq("id", venueId).maybeSingle();
  return resolveCityName(supabase, venue?.city_id as string | null | undefined);
}

async function loadEventVenueName(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  eventId: string,
): Promise<{ name: string | null; cityName: string | undefined }> {
  const { data: event } = await supabase.from("events").select("venue_id").eq("id", eventId).maybeSingle();
  if (!event?.venue_id) return { name: null, cityName: undefined };
  const { data: venue } = await supabase.from("venues").select("name, city_id").eq("id", event.venue_id).maybeSingle();
  return {
    name: (venue?.name as string | undefined) ?? null,
    cityName: await resolveCityName(supabase, venue?.city_id as string | null | undefined),
  };
}

/** Komponisten-Name für eine bessere Websuche-Anfrage bei Werken — reiner
 * Werktitel ist oft zu mehrdeutig ("Symphonie Nr. 5"), mit Komponist
 * deutlich treffsicherer. null bei jedem Fehler/fehlendem Komponisten. */
async function loadWorkComposerName(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  workId: string,
): Promise<string | null> {
  const { data: work } = await supabase.from("works").select("composer:persons(full_name)").eq("id", workId)
    .maybeSingle();
  const composer = work?.composer as { full_name?: string } | { full_name?: string }[] | null;
  if (!composer) return null;
  return (Array.isArray(composer) ? composer[0]?.full_name : composer.full_name) ?? null;
}

/** Breite KI-Websuche statt der bisher einzigen, engen Quellen (Wikipedia/
 * Commons/Wikidata — auf Nutzerfeedback: "wikipedia commons ist so
 * ungenau und hat oft keine bilder"). Nutzt Geminis "Grounding with Google
 * Search" — statt nur eine Website-URL zu finden (wie schon in
 * enrich-entity-images), wird hier direkt ein Bild GESUCHT: die echten,
 * von Google zitierten Quellen-URLs (Presse, Agentur-/Künstlerseiten,
 * Konzerthaus-Galerien, News-Artikel, ...) werden der Reihe nach auf ein
 * og:image geprüft, bis eins erreichbar ist. Deutlich breiter als die
 * kuratierten Wikimedia-Quellen, weil es das GESAMTE offene Web einbezieht,
 * nicht nur Artikel mit Wikipedia-/Wikidata-Eintrag — die meisten
 * Münchner Ensembles/Venues und viele (noch) lebende Musiker:innen haben
 * genau das nicht.
 *
 * Eigenes Secret GEMINI_IMAGE_SEARCH_API_KEY statt des in
 * enrich-entity-images für Website-URL-Discovery genutzten
 * GEMINI_SEARCH_API_KEY — bewusst getrennt, sonst konkurriert die
 * interaktive Bilder-Recherche mit dem alle 15 Minuten laufenden Cronjob
 * um dasselbe Tageskontingent (live beobachtet: 429 RESOURCE_EXHAUSTED
 * beim ersten Testaufruf, weil der Cronjob das gemeinsame Kontingent schon
 * ausgeschöpft hatte). Gleiches Prinzip wie schon die Trennung von
 * GEMINI_API_KEY vs. GEMINI_SEARCH_API_KEY, siehe geminiGroundedSearch.ts.
 *
 * null, wenn kein Key gesetzt ist, die Suche fehlschlägt, oder keine der
 * zitierten Seiten ein nutzbares Bild liefert — Aufrufer fallen dann auf
 * die bisherige Wikimedia-Kaskade zurück (bleibt als Sicherheitsnetz
 * bestehen, gerade für gemeinfreie historische Komponisten-Porträts oft
 * die zuverlässigste Quelle). */
/** Probiert bis zu 4 Kandidaten-Seiten-URLs der Reihe nach auf ein
 * erreichbares og:image, erste gewinnt — geteilte Auswertungslogik für
 * beide Websuch-Quellen unten (bewusst mehrere statt nur die erste, da
 * nicht jede zitierte Seite selbst ein Bild setzt, z.B. reine
 * Textquellen/PDFs). */
async function firstImageFromCandidates(
  candidates: { url: string; title: string | null }[],
  sourceLabel: string,
): Promise<SearchResult | null> {
  for (const candidate of candidates.slice(0, 4)) {
    if (!isPublicImageUrl(candidate.url)) continue;
    const imageUrl = await extractOgImage(candidate.url);
    if (!imageUrl) continue;
    const { reachable } = await checkImageUrl(imageUrl);
    if (!reachable) continue;
    return {
      found: true,
      imageUrl,
      sourcePageUrl: candidate.url,
      sourceName: new URL(candidate.url).hostname,
      matchReason: `${sourceLabel}${candidate.title ? ` — „${candidate.title}“` : ""}`,
    };
  }
  return null;
}

async function searchImageViaGroundedWeb(
  query: string,
  sourceLabel: string,
): Promise<SearchResult | null> {
  // DuckDuckGo zuerst — braucht kein Konto/API-Key/Kontingent (auf
  // Nutzerwunsch: "brauchen wir hierfür echt ein google konto? geht das
  // nicht auch mit scrapern"), im Gegensatz zu Gemini-Grounding sofort und
  // ohne jede Voraussetzung nutzbar. War bisher nur ein selten wirksamer
  // Notnagel für die reine URL-Suche (siehe enrich-entity-images), aber
  // dieselbe Quelle funktioniert für die Bildersuche genauso gut/schlecht
  // wie für die URL-Suche — hier als GLEICHWERTIGE erste Quelle, nicht nur
  // Fallback.
  const ddgResults = await searchDuckDuckGo(query, 4);
  if (ddgResults && ddgResults.length > 0) {
    const found = await firstImageFromCandidates(
      ddgResults.map((r) => ({ url: r.url, title: null })),
      `Websuche (${sourceLabel})`,
    );
    if (found) return found;
  }

  // Gemini-Grounding als optionale Ergänzung, NUR wenn ein eigener Key
  // gesetzt ist (GEMINI_IMAGE_SEARCH_API_KEY, getrennt vom Cronjob-
  // Kontingent, siehe Kommentar bei Deno.env.get unten) — bewusst NICHT
  // Voraussetzung fürs Funktionieren dieser Funktion.
  const apiKey = Deno.env.get("GEMINI_IMAGE_SEARCH_API_KEY");
  if (!apiKey) return null;
  const groundedResults = await searchViaGeminiGrounding(apiKey, query);
  if (!groundedResults || groundedResults.length === 0) return null;
  return firstImageFromCandidates(groundedResults, `KI-Websuche (${sourceLabel})`);
}

// Tier-0 (offizielle Website) trägt schon ihren eigenen 0–10-Score aus
// officialSiteImageSearch.ts. Die übrigen kuratierten Quellen (Wikipedia/
// Wikidata/Commons) liefern keinen eigenen Bild-Score — feste Werte, die
// dieselbe implizite Rangfolge abbilden, in der sie bisher sequenziell
// versucht wurden (z.B. Wikipedia vor Wikidata bei Personen), damit ein
// gleichzeitiger Treffer beider Quellen weiterhin dieselbe Quelle gewinnt
// wie vorher — der eigentliche Gewinn ist Parallelität (Geschwindigkeit),
// nicht eine neue Rangfolge unter den kuratierten Quellen.
const SOURCE_SCORE = {
  wikipedia: 8,
  wikidataOrCommonsFirst: 8,
  wikidataSecond: 7,
  groundedWeb: 5,
} as const;

/** Vereinheitlichtes Logging für ein ganzes Quellen-Rennen: jeder Versuch
 * (gefunden/nicht gefunden/Fehler) wird protokolliert, unabhängig vom
 * Gewinner — ersetzt die frühere Kette einzelner log()-Aufrufe direkt nach
 * jedem sequenziellen await. */
function logRaceAttempts(
  attempts: RaceImageSourcesResult<SearchResult>["attempts"],
  log: (entry: RunLogEntry) => void,
) {
  for (const a of attempts) {
    if (a.outcome === "found") {
      log({ source: a.source, outcome: "found", detail: `Score ${a.score.toFixed(1)}` });
    } else if (a.outcome === "error") {
      log({ source: a.source, outcome: "error", detail: a.detail });
    } else {
      log({ source: a.source, outcome: "not_found" });
    }
  }
}

async function searchWithoutPreview(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  entity: { name: string; websiteUrl: string | null; ticketUrl: string | null },
  entityType: EntityType,
  entityId: string,
  sourceUrlOverride: string | undefined,
  runLog: RunLogEntry[],
): Promise<SearchResult> {
  const log = (entry: RunLogEntry) => runLog.push(entry);

  // Admin hat einen konkreten Link gegeben — nur DIESE Seite auswerten,
  // keine eigenständige Recherche.
  if (sourceUrlOverride) {
    // Ein direkt kopierter Bildlink besitzt naturgemäß kein og:image.
    // Früher wurde er deshalb immer als "nichts gefunden" abgelehnt.
    const directImage = await checkImageUrl(sourceUrlOverride);
    const imageUrl = directImage.reachable ? sourceUrlOverride : await extractOgImage(sourceUrlOverride);
    if (!imageUrl) {
      log({ source: "Manueller Link", outcome: "not_found", detail: sourceUrlOverride });
      return { found: false, error: "Auf dieser Seite wurde kein verwendbares Bild gefunden." };
    }
    log({ source: "Manueller Link", outcome: "found", detail: sourceUrlOverride });
    return {
      found: true,
      imageUrl,
      sourcePageUrl: sourceUrlOverride,
      sourceName: new URL(sourceUrlOverride).hostname,
      matchReason: directImage.reachable ? "Manuell angegebener direkter Bildlink" : "Bild der manuell angegebenen Seite",
    };
  }

  // Verarbeitungsreihenfolge Schritt 1 (Nutzervorgabe): schon ein
  // bestätigtes Bild für GENAU diese Entität vorhanden? Dann direkt
  // wiederverwenden statt jede automatische Quelle erneut zu bemühen. Für
  // redaktionelle Sammlungen (keine recherchierbare reale Entität) sinnlos,
  // dort bleibt es bei Link/Upload.
  if (entityType !== "editorial_collection") {
    const existing = await findExistingConfirmedImage(supabase, entityType, entityId);
    if (existing) {
      log({ source: "Zentrale Bilddatenbank", outcome: "found", detail: "bereits bestätigtes Bild wiederverwendet" });
      return existing;
    }
    log({ source: "Zentrale Bilddatenbank", outcome: "not_found" });
  }

  switch (entityType) {
    case "person": {
      // Alle Quellen laufen parallel (Nutzerwunsch: "alle Quellen parallel
      // ... bestes Ergebnis nach Score wählen, statt beim ersten Treffer zu
      // stoppen"). Die offizielle Website bleibt aber Tier 0 und schlägt
      // JEDEN Tier-1/2-Treffer, unabhängig vom Score — siehe Kommentar bei
      // searchOfficialSite(): sie ist identitätssicherer, nicht nur
      // bildqualitativ besser, ein namensgleicher falscher Wikipedia-Treffer
      // darf sie nie verdrängen.
      const sources: ImageSourceAttempt<SearchResult>[] = [];
      if (entity.websiteUrl) {
        const websiteUrl = entity.websiteUrl;
        sources.push({
          source: "Künstlerseite (offizielle Website)",
          tier: 0,
          run: async () => {
            const official = await searchOfficialSite(entity.name, websiteUrl, "Künstlerseite", log);
            return official ? { candidate: official.result, score: official.score } : null;
          },
        });
      } else {
        log({ source: "Offizielle Website", outcome: "skipped", detail: "keine website_url hinterlegt" });
      }

      // Tier 1: Wikipedia/Wikidata — die zuverlässigsten Quellen für
      // Personen mit eigenem Artikel, kein Kontingent/Konto nötig.
      sources.push({
        source: "Wikipedia",
        tier: 1,
        run: async () => {
          const portrait = await fetchWikipediaPortrait(entity.name);
          if (!portrait) return null;
          return {
            score: SOURCE_SCORE.wikipedia,
            candidate: {
              found: true,
              imageUrl: portrait.imageUrl,
              sourcePageUrl: portrait.pageUrl,
              sourceName: "Wikipedia",
              matchReason: portrait.description ?? "Wikipedia-Infobox-Bild",
              suggestedLicenseStatus: "confirmed_licensed",
            },
          };
        },
      });
      sources.push({
        source: "Wikidata/Wikimedia Commons",
        tier: 1,
        run: async () => {
          const wikidata = await searchWikidataImage(entity.name);
          if (!wikidata) return null;
          return {
            score: SOURCE_SCORE.wikidataSecond,
            candidate: {
              found: true,
              imageUrl: wikidata.url,
              sourcePageUrl: wikidata.pageUrl,
              sourceName: "Wikidata/Wikimedia Commons",
              matchReason: `Strukturiertes Wikidata-Bild · Lizenz: ${wikidata.license}${wikidata.artist ? ` · ${wikidata.artist}` : ""}`,
              suggestedLicenseStatus: "confirmed_free",
            },
          };
        },
      });

      // Tier 2: breite KI-/Websuche als letzter Versuch (Nutzerfeedback:
      // "wikipedia commons ist so ungenau und hat oft keine bilder" — deckt
      // Musiker:innen ohne eigenen Wikipedia-Artikel und ohne (bekannte)
      // eigene Website ab).
      sources.push({
        source: "Websuche (DuckDuckGo/Gemini)",
        tier: 2,
        run: async () => {
          const grounded = await searchImageViaGroundedWeb(
            `${entity.name} Foto Porträt Musiker Klassik`,
            "Presse/Künstlerseite",
          );
          return grounded ? { candidate: grounded, score: SOURCE_SCORE.groundedWeb } : null;
        },
      });

      const race = await raceImageSources(sources);
      logRaceAttempts(race.attempts, log);
      if (race.winner) return race.winner.candidate;
      return { found: false, error: "Weder Wikipedia, Wikidata, die offizielle Website noch die Websuche liefern ein Bild." };
    }
    case "venue":
    case "ensemble": {
      // Venues bekommen die tatsächliche Stadt als Zusatzkontext gegen
      // Namensgleichheiten mit anderen Städten — live bestätigt, dass ohne
      // Kontext die Commons-Volltextsuche nach "Residenztheater" das
      // Residenztheater GERA statt München traf. Ensembles bewusst OHNE
      // Kontext (wie im Cron-Pendant, enrich-entity-images.ts): ein
      // auswärtiges Gastensemble soll nicht künstlich auf eine Stadt
      // verengt werden.
      // Bug-Fund: hier stand bisher fest "München", unabhängig von der
      // tatsächlichen Stadt der Venue — seit der Multi-City-Erweiterung
      // (Berlin/Hamburg/Wien/Frankfurt) dadurch für jede Venue außerhalb
      // Münchens falsch statt nur ungenau.
      const queryContext = entityType === "venue" ? await resolveVenueCityName(supabase, entityId) : undefined;
      const commonsQuery = queryContext ? `${entity.name} ${queryContext}` : entity.name;

      const sources: ImageSourceAttempt<SearchResult>[] = [];
      if (entity.websiteUrl) {
        const websiteUrl = entity.websiteUrl;
        const sourceLabel = entityType === "venue" ? "Veranstaltungsort" : "Ensemble";
        sources.push({
          source: `${sourceLabel} (offizielle Website)`,
          tier: 0,
          run: async () => {
            const official = await searchOfficialSite(entity.name, websiteUrl, sourceLabel, log);
            return official ? { candidate: official.result, score: official.score } : null;
          },
        });
      } else {
        log({ source: "Offizielle Website", outcome: "skipped", detail: "keine website_url hinterlegt" });
      }

      sources.push({
        source: "Wikimedia Commons",
        tier: 1,
        run: async () => {
          const candidate = await searchCommonsImage(commonsQuery);
          if (!candidate) return null;
          return {
            score: SOURCE_SCORE.wikidataOrCommonsFirst,
            candidate: {
              found: true,
              imageUrl: candidate.url,
              sourcePageUrl: candidate.pageUrl,
              sourceName: "Wikimedia Commons",
              matchReason: `Lizenz: ${candidate.license}${candidate.artist ? ` · ${candidate.artist}` : ""}`,
              suggestedLicenseStatus: "confirmed_free",
            },
          };
        },
      });
      sources.push({
        source: "Wikidata/Wikimedia Commons",
        tier: 1,
        run: async () => {
          const wikidata = await searchWikidataImage(entity.name, queryContext);
          if (!wikidata) return null;
          return {
            score: SOURCE_SCORE.wikidataSecond,
            candidate: {
              found: true,
              imageUrl: wikidata.url,
              sourcePageUrl: wikidata.pageUrl,
              sourceName: "Wikidata/Wikimedia Commons",
              matchReason: `Strukturiertes Wikidata-Bild · Lizenz: ${wikidata.license}${wikidata.artist ? ` · ${wikidata.artist}` : ""}`,
              suggestedLicenseStatus: "confirmed_free",
            },
          };
        },
      });
      sources.push({
        source: "Websuche (DuckDuckGo/Gemini)",
        tier: 2,
        run: async () => {
          const grounded = await searchImageViaGroundedWeb(
            `${entity.name}${queryContext ? ` ${queryContext}` : ""} Foto`,
            entityType === "venue" ? "Veranstaltungsort-Presse" : "Ensemble-Presse",
          );
          return grounded ? { candidate: grounded, score: SOURCE_SCORE.groundedWeb } : null;
        },
      });

      const race = await raceImageSources(sources);
      logRaceAttempts(race.attempts, log);
      if (race.winner) return race.winner.candidate;
      return { found: false, error: "Weder Wikimedia Commons/Wikidata, die offizielle Website noch die Websuche liefern ein Bild." };
    }
    case "event": {
      // Die eigene Veranstaltungsseite bleibt bewusst der erste Schritt
      // (kein Entitäts-Crawl — ein Event hat keine "offizielle Website" im
      // Sinne von officialSiteImageSearch.ts, sondern höchstens eine
      // eigene Ankündigungs-/Ticketseite mit einem einzigen relevanten
      // Bild, siehe coverImageDetection.ts für dieselbe Grundidee bei der
      // automatisierten Ingestion).
      const pageUrl = entity.websiteUrl ?? entity.ticketUrl;
      const sources: ImageSourceAttempt<SearchResult>[] = [];
      if (pageUrl) {
        sources.push({
          source: "Veranstaltungsseite",
          tier: 0,
          run: async () => {
            const ownImage = await extractOgImage(pageUrl);
            if (!ownImage) return null;
            return {
              score: 10,
              candidate: {
                found: true,
                imageUrl: ownImage,
                sourcePageUrl: pageUrl,
                sourceName: new URL(pageUrl).hostname,
                matchReason: "og:image der Veranstaltungsseite",
              },
            };
          },
        });
      } else {
        log({ source: "Veranstaltungsseite", outcome: "skipped" });
      }
      sources.push({
        source: "Websuche (DuckDuckGo/Gemini)",
        tier: 1,
        run: async () => {
          const venue = await loadEventVenueName(supabase, entityId);
          const grounded = await searchImageViaGroundedWeb(
            `${entity.name}${venue.name ? ` ${venue.name}` : ""}${venue.cityName ? ` ${venue.cityName}` : ""} Konzert`,
            "Presse/Ankündigung",
          );
          return grounded ? { candidate: grounded, score: SOURCE_SCORE.groundedWeb } : null;
        },
      });
      // Rückfall auf das Venue-Foto (Nutzerfeedback: mehr als nur eine
      // Quelle probieren) — bewusst die niedrigste Tier: das ist ein Foto
      // des VERANSTALTUNGSORTS, nicht der eigentlichen Veranstaltung, und
      // soll deshalb nie einen echten Treffer der beiden Quellen oben
      // verdrängen, egal wie hoch dessen Score wäre.
      sources.push({
        source: "Venue-Foto (Rückfall)",
        tier: 2,
        run: async () => {
          const venueFallback = await venuePhotoFallback(supabase, entityId);
          return venueFallback ? { candidate: venueFallback, score: 1 } : null;
        },
      });

      const race = await raceImageSources(sources);
      logRaceAttempts(race.attempts, log);
      if (race.winner) return race.winner.candidate;
      return {
        found: false,
        error: "Weder Veranstaltungsseite, Websuche noch der Veranstaltungsort liefern ein Bild.",
      };
    }
    case "work": {
      // Werke haben oft keinen eigenständigen, exakt betitelten Wikipedia-
      // Artikel (viele Titel sind mehrdeutig/uneindeutig) — Wikipedia
      // (funktioniert gut für bekannte Einzelwerke mit eigenem Artikel,
      // z. B. Opern/Oratorien), sonst Commons-Volltextsuche als breiterer
      // Fallback (Aufführungsfotos, Partitur-/Notenblatt-Scans, Plakate).
      // Keine offizielle-Website-Stufe — Werke haben keine eigene
      // website_url-Spalte (siehe HAS_WEBSITE_URL).
      const sources: ImageSourceAttempt<SearchResult>[] = [
        {
          source: "Wikipedia",
          tier: 0,
          run: async () => {
            const portrait = await fetchWikipediaPortrait(entity.name);
            if (!portrait) return null;
            return {
              score: SOURCE_SCORE.wikipedia,
              candidate: {
                found: true,
                imageUrl: portrait.imageUrl,
                sourcePageUrl: portrait.pageUrl,
                sourceName: "Wikipedia",
                matchReason: portrait.description ?? "Wikipedia-Infobox-Bild",
                suggestedLicenseStatus: "confirmed_licensed",
              },
            };
          },
        },
        {
          source: "Wikimedia Commons",
          tier: 1,
          run: async () => {
            const candidate = await searchCommonsImage(entity.name);
            if (!candidate) return null;
            return {
              score: SOURCE_SCORE.wikidataOrCommonsFirst,
              candidate: {
                found: true,
                imageUrl: candidate.url,
                sourcePageUrl: candidate.pageUrl,
                sourceName: "Wikimedia Commons",
                matchReason: `Lizenz: ${candidate.license}${candidate.artist ? ` · ${candidate.artist}` : ""}`,
                suggestedLicenseStatus: "confirmed_free",
              },
            };
          },
        },
        {
          source: "Wikidata/Wikimedia Commons",
          tier: 1,
          run: async () => {
            const wikidata = await searchWikidataImage(entity.name);
            if (!wikidata) return null;
            return {
              score: SOURCE_SCORE.wikidataSecond,
              candidate: {
                found: true,
                imageUrl: wikidata.url,
                sourcePageUrl: wikidata.pageUrl,
                sourceName: "Wikidata/Wikimedia Commons",
                matchReason: `Strukturiertes Wikidata-Bild · Lizenz: ${wikidata.license}${wikidata.artist ? ` · ${wikidata.artist}` : ""}`,
                suggestedLicenseStatus: "confirmed_free",
              },
            };
          },
        },
        {
          source: "Websuche (DuckDuckGo/Gemini)",
          tier: 2,
          run: async () => {
            const composerName = await loadWorkComposerName(supabase, entityId);
            const grounded = await searchImageViaGroundedWeb(
              `${entity.name}${composerName ? ` ${composerName}` : ""} Aufführung Foto`,
              "Aufführung/Programmheft",
            );
            return grounded ? { candidate: grounded, score: SOURCE_SCORE.groundedWeb } : null;
          },
        },
      ];

      const race = await raceImageSources(sources);
      logRaceAttempts(race.attempts, log);
      if (race.winner) return race.winner.candidate;
      return { found: false, error: "Weder Wikipedia, Wikimedia Commons, Wikidata noch die Websuche liefern ein Bild." };
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

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

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

    const { id: imageId, reason: failureReason } = await ensureCoverImageWithReason(supabase, {
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
        JSON.stringify({ committed: false, error: commitFailureMessage(failureReason) }),
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
