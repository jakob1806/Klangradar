// Lädt ein erkanntes Coverbild herunter, dedupliziert es (source_url dann
// pHash), speichert Original + WebP-Thumbnail in Supabase Storage und
// legt die zugehörige images-Zeile an (20260819000003_images_and_tags.sql,
// erweitert um width/height/mime_type/credits/license/phash/thumbnail_path
// in 20260909000001_image_cover_pipeline.sql).
//
// Bildverarbeitung (Decode/Resize/WebP-Encode) läuft über
// npm:@imagemagick/magick-wasm — die einzige in der Supabase-Edge-Runtime
// unterstützte Bildbibliothek (WASM, keine native Bindings wie bei sharp;
// siehe Supabase-Doku "Edge Functions currently doesn't support image
// processing libraries such as Sharp"). Es gibt im Projekt bisher keinerlei
// Bildverarbeitungscode zum Wiederverwenden — diese eine neue Abhängigkeit
// ist unvermeidlich für Download+WebP+Thumbnail+Hash.
//
// Best-effort wie das bisherige recordImage() in ingest-source/write.ts:
// jeder Fehlschlag (nicht erreichbar, Decode-Fehler, Storage-Fehler) liefert
// null zurück, wirft nie — der Aufrufer entscheidet, ob dann auf die
// URL-only-Zeile bzw. die Fallback-Kaskade zurückgefallen wird.

import {
  ImageMagick,
  initializeImageMagick,
  MagickFormat,
} from "npm:@imagemagick/magick-wasm@0.0.31";
import { checkImageUrl, isPublicImageUrl } from "./imageValidation.ts";
import { USER_AGENT } from "./robots.ts";

const MAX_IMAGE_BYTES = 15_000_000;
const THUMBNAIL_SIZE = 400;
const PHASH_IMAGE_SIZE = 32;
const PHASH_HASH_SIZE = 8; // 8x8 niedrigfrequente Koeffizienten -> 64 Bit
export const BUCKET = "ingested-images";

const MIN_WIDTH = 640;
const MIN_HEIGHT = 480;
const MIN_ASPECT_RATIO = 0.4;
const MAX_ASPECT_RATIO = 3.0;

// Nutzerfeedback: "oft sind die Bilder komplett falsch, unscharf oder..." —
// die pHash-Auflösung (32x32) ist für eine Schärfemessung zu klein (fast
// jedes Bild wirkt bei 32x32 "unscharf", da schon das Downscaling selbst
// hochfrequente Details entfernt). 256px auf der langen Kante behält genug
// Struktur für eine sinnvolle Laplacian-Varianz, ohne den zusätzlichen
// Decode-Aufwand relevant zu erhöhen.
const SHARPNESS_IMAGE_SIZE = 256;
// Startwert bewusst konservativ (lieber ein paar echte Grenzfälle
// durchlassen als scharfe Bilder fälschlich ablehnen) — sollte anhand
// echter freigegebener vs. abgelehnter Bilder aus der Produktion
// nachkalibriert werden, sobald quality_status='blurry' erste Daten liefert.
const MIN_SHARPNESS_VARIANCE = 60;

/** Reine Prüf-Funktion, siehe imagePipeline.test.ts — getrennt von
 * ensureCoverImage(), damit sie ohne Supabase-Client/Storage/ImageMagick
 * testbar ist. Abschnitt 3 der Gesamtüberarbeitung: "Mindestauflösung/
 * Seitenverhältnis prüfen". Ohne Seitenverhältnis-Grenze rutschen extrem
 * breite Banner oder hohe Sidebar-Grafiken durch, die einzeln beide
 * Mindestmaße noch erfüllen, aber kein brauchbares Foto sind. 0.4–3.0 lässt
 * normales Hoch-/Querformat durch (typische Presse-/Veranstaltungsfotos
 * liegen zwischen 3:4 und 16:9). */
export function isAcceptableImageDimensions(width: number, height: number): boolean {
  if (width < MIN_WIDTH || height < MIN_HEIGHT) return false;
  const aspectRatio = width / height;
  return aspectRatio >= MIN_ASPECT_RATIO && aspectRatio <= MAX_ASPECT_RATIO;
}

let magickReady: Promise<void> | null = null;

/** Lazy, einmalige Initialisierung pro Isolate — initializeImageMagick() darf
 * nur einmal aufgerufen werden, aber Edge-Function-Isolates werden zwischen
 * "warmen" Invocations wiederverwendet, ein modulweiter Singleton-Promise
 * reicht deshalb aus (kein zusätzlicher Caching-Layer nötig). */
export function ensureMagickReady(): Promise<void> {
  if (!magickReady) {
    magickReady = (async () => {
      const wasmBytes = await Deno.readFile(
        new URL(
          "magick.wasm",
          import.meta.resolve("npm:@imagemagick/magick-wasm@0.0.31"),
        ),
      );
      await initializeImageMagick(wasmBytes);
    })();
  }
  return magickReady;
}

// Nutzerfeedback: der manuelle Datei-Upload in "Bilder recherchieren"
// scheitert oft mit der immer gleichen, generischen Meldung ("nicht
// verarbeitet werden konnte, nicht erreichbar, zu klein, oder ungültiges
// Format") — ensureCoverImage() gibt bei JEDEM der ~8 unterschiedlichen
// Fehlschlagsgründe stumm null zurück, die Redaktion kann nie erkennen,
// welcher der vier genannten Gründe tatsächlich zutraf. reason macht den
// tatsächlichen Grund für die interaktiven Aufrufer (research-entity-image
// commit-Pfad) sichtbar, ohne das bisherige "wirft nie, liefert bei jedem
// Fehlschlag null"-Verhalten der Hintergrund-Aufrufer (ingest-source,
// enrich-entity-images) zu ändern — ensureCoverImage() bleibt für die
// unverändert string|null.
export type CoverImageFailureReason =
  | "unreachable"
  | "download_failed"
  | "decode_failed"
  | "too_small"
  | "bad_aspect_ratio"
  | "too_blurry"
  | "storage_error"
  | "unknown";

export type ImageOriginType =
  | "event"
  | "venue"
  | "ensemble"
  | "person"
  | "organizer"
  | "festival"
  | "work"
  | "editorial_collection";

export interface CoverImageInput {
  sourceUrl: string;
  originType: ImageOriginType;
  originId: string;
  /** Wenn gesetzt, wird NICHT von sourceUrl heruntergeladen — für manuelle
   * Admin-Uploads (research-entity-image/index.ts), wo die Bilddatei schon
   * lokal vorliegt. sourceUrl dient in diesem Fall nur noch als
   * Anzeige-/Dedupe-Schlüssel (z.B. "manual-upload:<random>"), nicht als
   * abrufbare URL. */
  sourceBytes?: Uint8Array;
  credits?: string | null;
  sourcePageUrl?: string | null;
  sourceName?: string | null;
  photographer?: string | null;
  licenseName?: string | null;
  licenseUrl?: string | null;
  licenseStatus?:
    | "confirmed_free"
    | "confirmed_licensed"
    | "official_press_image"
    | "permission_required"
    | "unknown";
  confidenceScore?: number | null;
  matchReason?: string | null;
  warnings?: string[];
  needsReview?: boolean;
}

interface CoverImageResult {
  id: string | null;
  reason?: CoverImageFailureReason;
}

/** Liefert die images.id des (ggf. wiederverwendeten) Coverbilds, oder null
 * bei jedem Fehlschlag — nie eine geworfene Exception, siehe Datei-Kommentar.
 * Unverändertes Verhalten für die bestehenden Hintergrund-Aufrufer
 * (ingest-source, enrich-entity-images), die den Grund nie ausgewertet
 * haben. Für den interaktiven Upload-Pfad siehe ensureCoverImageWithReason. */
export async function ensureCoverImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  input: CoverImageInput,
): Promise<string | null> {
  const result = await ensureCoverImageWithReason(supabase, input);
  return result.id;
}

/** Wie ensureCoverImage(), liefert aber zusätzlich den konkreten Grund eines
 * Fehlschlags — für den interaktiven Kommentar in der Fehlermeldung des
 * manuellen Upload-Pfads (research-entity-image, mode="commit"), siehe
 * Datei-Kommentar oben (CoverImageFailureReason). */
export async function ensureCoverImageWithReason(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  input: CoverImageInput,
): Promise<CoverImageResult> {
  try {
    return await ensureCoverImageInner(supabase, input);
  } catch (err) {
    console.error(
      `ensureCoverImage failed for ${input.sourceUrl}: ${
        err instanceof Error ? err.message : String(err)
      }`,
    );
    return { id: null, reason: "unknown" };
  }
}

async function ensureCoverImageInner(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  input: CoverImageInput,
): Promise<CoverImageResult> {
  const { sourceUrl, originType, originId } = input;

  // 1. Exakte source_url für dasselbe Origin schon bekannt? Direkt
  // wiederverwenden, kein erneuter Download/keine erneute Verarbeitung.
  // review_status=rejected ausgeschlossen: eine Redakteurin hat dieses Bild
  // für diese Entität bereits explizit abgelehnt — wird dieselbe URL später
  // erneut gefunden (z.B. dieselbe Wikipedia-Infobox bei einer erneuten
  // Recherche), darf NICHT stillschweigend dieselbe abgelehnte Zeile
  // "wiederbelebt" werden (Nutzervorgabe, Testfall 12: "ein Bild wird
  // abgelehnt und darf nicht automatisch erneut vorgeschlagen werden").
  // Fällt stattdessen durch zur normalen Verarbeitung weiter unten, die bei
  // identischem Inhalt regulär eine frische Zeile mit Default-Status anlegt.
  const { data: existingByUrl } = await supabase
    .from("images")
    .select("id, storage_path")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .eq("source_url", sourceUrl)
    .neq("review_status", "rejected")
    .maybeSingle();
  if (existingByUrl?.storage_path) return { id: existingByUrl.id };

  let bytes: Uint8Array | null;
  let mimeTypeHint: string | null = null;
  if (input.sourceBytes) {
    bytes = input.sourceBytes;
  } else {
    const check = await checkImageUrl(sourceUrl);
    if (!check.reachable) return { id: null, reason: "unreachable" };
    mimeTypeHint = check.contentType ?? null;
    bytes = await downloadImage(sourceUrl);
  }
  if (!bytes) return { id: null, reason: "download_failed" };
  const contentHash = await sha256(bytes);

  // Schon eine Zeile für GENAU dieses Origin mit exakt diesem Bildinhalt
  // vorhanden (nur eine andere source_url, z.B. weil eine Quelle bei jedem
  // Abruf einen neuen Cache-Busting-Dateinamen für dasselbe Bild liefert)?
  // Dann NICHTS Neues anlegen — live beobachtet: eine oft re-ingestete,
  // authoritative Quelle (raw.imageUrl direkt aus dem Feed, siehe
  // ingest-source/write.ts attachCoverImage) erzeugte bei jedem Lauf eine
  // weitere needs_review-Zeile mit identischem Inhalt für dasselbe Event,
  // weil der exakte-source_url-Vergleich oben (existingByUrl) die
  // geänderte URL nicht traf. Mehrere fast identische Karten in der
  // /media-Review-Queue für ein einziges Event waren die Folge.
  // review_status=rejected ausgeschlossen — gleicher Grund wie beim
  // exakten URL-Dedupe oben, nur hier für den Fall einer leicht
  // geänderten URL (Cache-Busting) desselben, bereits abgelehnten Inhalts.
  const { data: existingForOrigin } = await supabase
    .from("images")
    .select("id, storage_path, thumbnail_path")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .eq("content_hash", contentHash)
    .not("storage_path", "is", null)
    .neq("review_status", "rejected")
    .limit(1)
    .maybeSingle();
  if (existingForOrigin?.storage_path) {
    if (!existingForOrigin.thumbnail_path) {
      // Gleiche Selbstheilung wie im Cross-Origin-Dedupe-Pfad unten — die
      // Bytes liegen hier schon vor, kein zusätzlicher Download nötig.
      await ensureMagickReady();
      const decoded = decodeImage(bytes);
      if (decoded) {
        const backfillPath = `${originType}/${crypto.randomUUID()}-thumb.webp`;
        const { error: backfillError } = await supabase.storage
          .from(BUCKET)
          .upload(backfillPath, decoded.thumbnailBytes, {
            contentType: "image/webp",
            upsert: false,
          });
        if (!backfillError) {
          await supabase.from("images").update({ thumbnail_path: backfillPath }).eq(
            "id",
            existingForOrigin.id,
          );
        }
      }
    }
    return { id: existingForOrigin.id };
  }

  const { data: existingByContentHash } = await supabase
    .from("images").select(
      "id, storage_path, thumbnail_path, width, height, mime_type, phash",
    ).eq("content_hash", contentHash)
    .not("storage_path", "is", null).limit(1).maybeSingle();
  if (existingByContentHash) {
    // Selbstheilung: wenn die Ursprungszeile mal ohne Thumbnail gelandet ist
    // (thumbError-Fall weiter unten — Hauptbild-Upload lief durch, nur die
    // Thumbnail-Generierung schlug fehl), würde dieser Pfad das kaputte
    // thumbnail_path=null sonst auf JEDE künftige Wiederverwendung desselben
    // Bildinhalts weitervererben (live beobachtet: dieselbe og:image-URL
    // wurde bei jedem Cron-Lauf erneut gefunden, jedes Mal eine neue
    // needs_review-Zeile mit demselben kaputten null-Thumbnail — mehrere
    // identische, alle im Review-Queue-Grid als kaputtes Bild-Icon
    // sichtbare Karten für dasselbe Event). Die Rohbytes liegen hier noch
    // vor (oben heruntergeladen) — Thumbnail einmalig nachträglich bauen
    // und auf der Ursprungszeile UND der neuen Zeile hinterlegen, statt den
    // Fehler stumm weiterzureichen.
    let thumbnailPath = existingByContentHash.thumbnail_path;
    if (!thumbnailPath) {
      await ensureMagickReady();
      const decoded = decodeImage(bytes);
      if (decoded) {
        const backfillPath = `${originType}/${crypto.randomUUID()}-thumb.webp`;
        const { error: backfillError } = await supabase.storage
          .from(BUCKET)
          .upload(backfillPath, decoded.thumbnailBytes, {
            contentType: "image/webp",
            upsert: false,
          });
        if (!backfillError) {
          thumbnailPath = backfillPath;
          await supabase.from("images").update({ thumbnail_path: backfillPath }).eq(
            "id",
            existingByContentHash.id,
          );
        }
      }
    }

    // Derselbe Blob darf wiederverwendet werden, die Provenienz-Zeile aber
    // nicht: origin_type/origin_id gehören immer zum aktuellen Datensatz.
    const { data: linked } = await supabase.from("images").insert({
      storage_path: existingByContentHash.storage_path,
      thumbnail_path: thumbnailPath,
      width: existingByContentHash.width,
      height: existingByContentHash.height,
      mime_type: existingByContentHash.mime_type,
      phash: existingByContentHash.phash,
      content_hash: contentHash,
      source_url: sourceUrl,
      original_image_url: sourceUrl,
      origin_type: originType,
      origin_id: originId,
      source_page_url: input.sourcePageUrl ?? null,
      source_name: input.sourceName ?? null,
      photographer: input.photographer ?? null,
      credits: input.credits ?? null,
      license_name: input.licenseName ?? null,
      license_url: input.licenseUrl ?? null,
      license_status: input.licenseStatus ?? "unknown",
      confidence_score: input.confidenceScore ?? null,
      match_reason: input.matchReason ?? null,
      warnings: [
        ...(input.warnings ?? []),
        "Identischer Bildinhalt war bereits im Storage vorhanden.",
      ],
      needs_review: input.needsReview ?? true,
    }).select("id").single();
    return linked ? { id: linked.id } : { id: null, reason: "storage_error" };
  }

  await ensureMagickReady();

  const decoded = decodeImage(bytes);
  if (!decoded) return { id: null, reason: "decode_failed" };
  const { width, height, webpBytes, thumbnailBytes, phash, sharpness } = decoded;
  if (width < 400 || height < 300) return { id: null, reason: "too_small" };

  // Nutzerfeedback: "die Bilder, die in der Detailansicht von einzelnen
  // Veranstaltungen in der App angezeigt werden sind noch etwas unscharf".
  // Ohne Mindestauflösung landet hier jedes noch so kleine Vorschaubild
  // einer Quelle (viele Event-Listing-Seiten liefern nur ein ~250-300px
  // breites Karten-Thumbnail als og:image/schema.org-Bild) im Speicher und
  // wird später auf die volle, bildschirmfüllende Hero-Breite der
  // Detailansicht hochskaliert — das wirkt zwangsläufig verwaschen. 640x480
  // lässt die meisten echten Pressefotos/Veranstaltungsbilder durch, sperrt
  // aber reine Listing-Thumbnails aus (dann bleibt der Genre-Platzhalter
  // sichtbar statt eines hochskalierten Kleinstbilds).
  if (!isAcceptableImageDimensions(width, height)) {
    // isAcceptableImageDimensions() bleibt die alleinige Quelle für die
    // Schwellwerte (siehe imagePipeline.test.ts) — hier nur zusätzlich
    // ermitteln, WELCHE der beiden Teilbedingungen zutraf, für eine genaue
    // Fehlermeldung statt des bisherigen einen kombinierten "zu klein".
    const aspectRatio = width / height;
    const reason: CoverImageFailureReason =
      width < MIN_WIDTH || height < MIN_HEIGHT ? "too_small" : "bad_aspect_ratio";
    console.error(
      `ensureCoverImage: rejected ${sourceUrl} (${width}x${height}, aspect ${
        aspectRatio.toFixed(2)
      }) — reason ${reason}`,
    );
    return { id: null, reason };
  }

  // Nutzerfeedback: "oft sind die Bilder komplett falsch, unscharf oder..."
  // — Laplacian-Varianz als Schärfe-Maß, zusätzlich zur reinen
  // Auflösungsprüfung oben (die fängt nur zu KLEINE Bilder ab, nicht
  // großformatige, aber verwaschene/verpixelte Treffer).
  if (sharpness < MIN_SHARPNESS_VARIANCE) {
    console.error(
      `ensureCoverImage: rejected ${sourceUrl} as too blurry (sharpness variance ${
        sharpness.toFixed(1)
      }, threshold ${MIN_SHARPNESS_VARIANCE})`,
    );
    return { id: null, reason: "too_blurry" };
  }

  // 2. pHash-Dedupe: dieselbe Bilddatei schon für irgendein Origin
  // gespeichert (z.B. über eine andere source_url oder ein anderes Event
  // derselben Quelle)? Dann die bestehende Zeile wiederverwenden statt
  // erneut hochzuladen. Exakter Hash-Vergleich (siehe Migration), kein
  // Hamming-Distanz-Scan über alle Zeilen.
  // review_status=rejected ausgeschlossen — sonst würde ein perzeptuell
  // identischer Re-Fund für dieselbe Entität (unterer Zweig: gleicher
  // origin_type/origin_id) die längst abgelehnte Zeile zurückliefern statt
  // sie zu ignorieren, gleicher Grund wie bei den beiden Dedupe-Stufen oben.
  const { data: existingByHash } = await supabase
    .from("images")
    .select("id, origin_type, origin_id")
    .eq("phash", phash)
    .not("storage_path", "is", null)
    .neq("review_status", "rejected")
    .limit(1)
    .maybeSingle();
  if (existingByHash) {
    return existingByHash.origin_type === originType &&
        existingByHash.origin_id === originId
      ? { id: existingByHash.id }
      : { id: null, reason: "unknown" };
  }

  const storagePath = `${originType}/${crypto.randomUUID()}.webp`;
  const thumbnailPath = `${originType}/${crypto.randomUUID()}-thumb.webp`;

  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(storagePath, webpBytes, {
      contentType: "image/webp",
      upsert: false,
    });
  if (uploadError) {
    console.error(
      `ensureCoverImage: upload failed for ${sourceUrl}: ${uploadError.message}`,
    );
    return { id: null, reason: "storage_error" };
  }

  let storedThumbnailPath: string | null = thumbnailPath;
  const { error: thumbError } = await supabase.storage
    .from(BUCKET)
    .upload(thumbnailPath, thumbnailBytes, {
      contentType: "image/webp",
      upsert: false,
    });
  if (thumbError) {
    // Hauptbild ist schon gespeichert — kein Grund, das komplett scheitern
    // zu lassen, nur ohne Thumbnail-Pfad weiterschreiben.
    console.error(
      `ensureCoverImage: thumbnail upload failed for ${sourceUrl}: ${thumbError.message}`,
    );
    storedThumbnailPath = null;
  }

  const { data: inserted, error: insertError } = await supabase
    .from("images")
    .insert({
      origin_type: originType,
      origin_id: originId,
      source_url: sourceUrl,
      storage_path: storagePath,
      thumbnail_path: storedThumbnailPath,
      width,
      height,
      mime_type: mimeTypeHint ?? "image/webp",
      phash,
      content_hash: contentHash,
      credits: input.credits ?? null,
      source_page_url: input.sourcePageUrl ?? null,
      source_name: input.sourceName ?? null,
      original_image_url: sourceUrl,
      photographer: input.photographer ?? null,
      license_name: input.licenseName ?? null,
      license_url: input.licenseUrl ?? null,
      license_status: input.licenseStatus ?? "unknown",
      confidence_score: input.confidenceScore ?? null,
      match_reason: input.matchReason ?? null,
      warnings: input.warnings ?? [],
      needs_review: input.needsReview ?? true,
      fetched_at: new Date().toISOString(),
      copyright_notice: extractCopyrightFromCredits(input.credits ?? null),
    })
    .select("id")
    .single();

  if (insertError || !inserted) {
    console.error(
      `ensureCoverImage: insert failed for ${sourceUrl}: ${
        insertError?.message ?? "unknown"
      }`,
    );
    return { id: null, reason: "storage_error" };
  }

  return { id: inserted.id };
}

// Kein Timeout hier bedeutete: ein einzelner langsamer/nie antwortender
// Server konnte den gesamten Lauf (Batch-Cron oder interaktive Admin-
// Recherche) auf unbestimmte Zeit blockieren, statt sauber mit "kein
// Bild" weiterzumachen — SSRF-Härtung (siehe isPublicImageUrl weiter
// oben) schützt vor ZIEL-Adressen, aber nicht vor einem antwortenden,
// aber absichtlich/versehentlich extrem langsamen Server. 20s pro
// Redirect-Hop UND für den finalen Body-Download, insgesamt also weich
// nach oben begrenzt durch die maximal 5 Hops.
const DOWNLOAD_TIMEOUT_MS = 20_000;

export async function downloadImage(url: string): Promise<Uint8Array | null> {
  try {
    let current = url;
    let res: Response | null = null;
    for (let redirects = 0; redirects <= 4; redirects++) {
      if (!isPublicImageUrl(current)) return null;
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), DOWNLOAD_TIMEOUT_MS);
      try {
        res = await fetch(current, {
          headers: { "User-Agent": USER_AGENT },
          redirect: "manual",
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }
      if (![301, 302, 303, 307, 308].includes(res.status)) break;
      const location = res.headers.get("location");
      if (!location) return null;
      current = new URL(location, current).toString();
      res = null;
    }
    if (!res) return null;
    if (!res.ok || !res.body) return null;
    const contentType = res.headers.get("content-type")?.split(";")[0]
      .toLowerCase();
    if (
      !contentType ||
      !["image/jpeg", "image/png", "image/webp", "image/avif"].includes(
        contentType,
      )
    ) return null;
    const contentLength = res.headers.get("content-length");
    if (contentLength && Number(contentLength) > MAX_IMAGE_BYTES) {
      await res.body.cancel().catch(() => {});
      return null;
    }
    const bodyController = new AbortController();
    const bodyTimeout = setTimeout(() => bodyController.abort(), DOWNLOAD_TIMEOUT_MS);
    let buf: ArrayBuffer;
    try {
      // res.arrayBuffer() nimmt kein eigenes AbortSignal — ein bereits
      // begonnener, aber hängender Body-Stream wird über res.body.cancel()
      // abgebrochen, sobald der Timeout feuert.
      const bodyPromise = res.arrayBuffer();
      const timeoutPromise = new Promise<never>((_, reject) => {
        bodyController.signal.addEventListener("abort", () => {
          res!.body?.cancel().catch(() => {});
          reject(new Error("download timed out"));
        });
      });
      buf = await Promise.race([bodyPromise, timeoutPromise]);
    } finally {
      clearTimeout(bodyTimeout);
    }
    if (buf.byteLength > MAX_IMAGE_BYTES) return null;
    return new Uint8Array(buf);
  } catch {
    return null;
  }
}

export async function sha256(bytes: Uint8Array): Promise<string> {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", copy.buffer);
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

interface DecodedImage {
  width: number;
  height: number;
  webpBytes: Uint8Array;
  thumbnailBytes: Uint8Array;
  phash: string;
  sharpness: number;
}

/** Vier unabhängige ImageMagick.read()-Aufrufe statt einmal lesen + klonen:
 * etwas mehr Decode-Aufwand, aber ohne Annahmen über Clone/Dispose-Details
 * der magick-wasm-API, die sich ansonsten schwer verifizieren lassen — jeder
 * read()-Aufruf verwaltet seine Ressourcen vollständig selbst, exakt wie im
 * offiziellen Supabase-Beispiel für Edge-Function-Bildverarbeitung. */
// Exportiert (statt modulintern), damit decodeImage() isoliert getestet
// werden kann — anders als ensureCoverImage() braucht es nur die WASM-
// Bibliothek, keinen echten Supabase-Client/Storage. Siehe
// imagePipeline.decode.test.ts für den Regressionstest zum WASM-Speicher-
// Aliasing-Bug (siehe Kommentar bei den write()-Aufrufen unten).
export function decodeImage(bytes: Uint8Array): DecodedImage | null {
  try {
    // .slice() ist Pflicht, kein Stil: der data-Parameter ist eine reine
    // Sicht auf WASM-Linearspeicher, die vom NÄCHSTEN ImageMagick-Aufruf
    // (hier: der thumbnailBytes-read() direkt danach) wiederverwendet/
    // überschrieben wird. Ohne Kopie enthielten die hochgeladenen "WebP"-
    // Dateien beim Upload bereits fremde/überschriebene Bytes statt der
    // tatsächlich kodierten Bilddaten — live bestätigt (falsche Magic
    // Bytes, Volltreffer-Duplikat zwischen full- und thumbnail-Datei
    // derselben Entität, weil beide dasselbe zuletzt überschriebene
    // Speicherstück zurückgaben).
    const full = ImageMagick.read(bytes, (img) => ({
      width: img.width,
      height: img.height,
      webpBytes: img.write(
        MagickFormat.WebP,
        (data: Uint8Array) => data.slice(),
      ) as unknown as Uint8Array,
    }));

    const thumbnailBytes = ImageMagick.read(bytes, (img) => {
      img.resize(THUMBNAIL_SIZE, THUMBNAIL_SIZE);
      return img.write(
        MagickFormat.WebP,
        (data: Uint8Array) => data.slice(),
      ) as unknown as Uint8Array;
    });

    const phash = ImageMagick.read(bytes, (img) => {
      img.resize(PHASH_IMAGE_SIZE, PHASH_IMAGE_SIZE);
      const rgb = img.getPixels((pixels) =>
        pixels.toByteArray(0, 0, PHASH_IMAGE_SIZE, PHASH_IMAGE_SIZE, "RGB")
      ) as unknown as Uint8Array;
      const gray = toGrayscale(rgb, PHASH_IMAGE_SIZE * PHASH_IMAGE_SIZE);
      return computeDctHash(gray, PHASH_IMAGE_SIZE);
    });

    // Eigener Read bei höherer Auflösung als der pHash (siehe
    // SHARPNESS_IMAGE_SIZE-Kommentar) — resize() skaliert wie bei den
    // anderen Reads oben in eine Bounding-Box unter Beibehaltung des
    // Seitenverhältnisses, deshalb img.width/img.height NACH dem Resize
    // statt der Konstante selbst für die Pixel-Extraktion verwenden.
    const sharpness = ImageMagick.read(bytes, (img) => {
      img.resize(SHARPNESS_IMAGE_SIZE, SHARPNESS_IMAGE_SIZE);
      const w = img.width;
      const h = img.height;
      const rgb = img.getPixels((pixels) =>
        pixels.toByteArray(0, 0, w, h, "RGB")
      ) as unknown as Uint8Array;
      const gray = toGrayscale(rgb, w * h);
      return computeSharpnessVariance(gray, w, h);
    });

    return {
      width: full.width,
      height: full.height,
      webpBytes: full.webpBytes,
      thumbnailBytes,
      phash,
      sharpness,
    };
  } catch (err) {
    console.error(
      `decodeImage failed: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
}

function toGrayscale(rgb: Uint8Array, pixelCount: number): Uint8Array {
  const gray = new Uint8Array(pixelCount);
  for (let i = 0; i < pixelCount; i++) {
    const r = rgb[i * 3] ?? 0;
    const g = rgb[i * 3 + 1] ?? 0;
    const b = rgb[i * 3 + 2] ?? 0;
    gray[i] = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
  }
  return gray;
}

/** Laplacian-Varianz als Schärfe-Maß — Standard-Heuristik zur Unschärfe-
 * Erkennung (z.B. "variance of Laplacian", verbreitet u.a. über OpenCV-
 * Tutorials). Der diskrete Laplace-Kernel (0,1,0 / 1,-4,1 / 0,1,0) reagiert
 * stark auf Kanten/Details und schwach auf gleichmäßige Flächen — ein
 * unscharfes/verpixeltes Bild hat wenig hochfrequente Struktur und damit
 * eine niedrige Varianz der Kernel-Antworten über das ganze Bild. Randpixel
 * werden ausgelassen (kein Padding/Wraparound nötig für eine reine
 * Schätzung, nicht für eine exakte Faltung). Reine Funktion ohne
 * ImageMagick-Bezug — exportiert für imagePipeline.test.ts. */
export function computeSharpnessVariance(
  gray: Uint8Array,
  width: number,
  height: number,
): number {
  if (width < 3 || height < 3) return 0;
  let sum = 0;
  let sumSquares = 0;
  let count = 0;
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const idx = y * width + x;
      const laplacian = -4 * gray[idx] +
        gray[idx - 1] +
        gray[idx + 1] +
        gray[idx - width] +
        gray[idx + width];
      sum += laplacian;
      sumSquares += laplacian * laplacian;
      count++;
    }
  }
  if (count === 0) return 0;
  const mean = sum / count;
  return sumSquares / count - mean * mean;
}

/** Klassischer pHash-Algorithmus (DCT-basiert) statt eines einfacheren
 * Average-Hash — deutlich robuster gegen genau den Fall, der hier häufig
 * vorkommt: dieselbe Bilddatei über verschiedene CMS/Quellen erneut
 * komprimiert/leicht skaliert ausgeliefert. 2D-DCT-II über das komplette
 * Graustufenbild, dann die niedrigfrequenten 8x8-Koeffizienten (ohne den
 * DC-Term) gegen ihren Median als 64-Bit-Hash kodiert — Standardverfahren
 * (z.B. von der pHash-Bibliothek/den meisten "imagehash"-Python-
 * Implementierungen genutzt), hier direkt nachgebaut, weil es dafür keine
 * fertige Deno/npm-Bibliothek für die Edge-Runtime gibt. */
function computeDctHash(gray: Uint8Array, size: number): string {
  const dct = dct2d(gray, size);

  const lowFreq: number[] = [];
  for (let y = 0; y < PHASH_HASH_SIZE; y++) {
    for (let x = 0; x < PHASH_HASH_SIZE; x++) {
      if (x === 0 && y === 0) continue; // DC-Term überspringen (nur Helligkeit, keine Struktur)
      lowFreq.push(dct[y * size + x]);
    }
  }

  const sorted = [...lowFreq].sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)];

  let hash = 0n;
  for (const value of lowFreq) {
    hash = (hash << 1n) | (value > median ? 1n : 0n);
  }
  return hash.toString(16).padStart(16, "0");
}

/** Separierbare 2D-DCT-II: 1D-Transformation zeilenweise, dann spaltenweise —
 * O(n^3) statt einer naiven O(n^4) 2D-Summe. Für n=32 (~33k Operationen pro
 * Richtung) unproblematisch für eine Hintergrund-Ingestion. */
function dct2d(pixels: Uint8Array, n: number): Float64Array {
  const rows = new Float64Array(n * n);
  for (let y = 0; y < n; y++) {
    const row = dct1d(pixels.subarray(y * n, y * n + n), n);
    rows.set(row, y * n);
  }

  const result = new Float64Array(n * n);
  const col = new Float64Array(n);
  for (let x = 0; x < n; x++) {
    for (let y = 0; y < n; y++) col[y] = rows[y * n + x];
    const transformed = dct1d(col, n);
    for (let y = 0; y < n; y++) result[y * n + x] = transformed[y];
  }
  return result;
}

function dct1d(input: ArrayLike<number>, n: number): Float64Array {
  const out = new Float64Array(n);
  for (let k = 0; k < n; k++) {
    let sum = 0;
    for (let i = 0; i < n; i++) {
      sum += input[i] * Math.cos((Math.PI / n) * (i + 0.5) * k);
    }
    out[k] = sum * (k === 0 ? Math.sqrt(1 / n) : Math.sqrt(2 / n));
  }
  return out;
}

/** Zieht einen reinen ©-Vermerk aus dem breiteren Credits-Text, falls
 * vorhanden — copyright_notice ist ein eigenes, schon vor dieser Erweiterung
 * bestehendes Feld (redaktionell genutzt), credits (neu) ist der breitere
 * Bildnachweis ("Foto: ...", "Photographer: ..."). Beide können denselben
 * Ursprungstext teilweise überlappen, deshalb hier nur der ©-Ausschnitt. */
function extractCopyrightFromCredits(credits: string | null): string | null {
  if (!credits) return null;
  const match = /©[^,;]{0,80}/.exec(credits);
  return match ? match[0].trim() : null;
}
