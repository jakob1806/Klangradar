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
const BUCKET = "ingested-images";

const MIN_WIDTH = 640;
const MIN_HEIGHT = 480;
const MIN_ASPECT_RATIO = 0.4;
const MAX_ASPECT_RATIO = 3.0;

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

/** Liefert die images.id des (ggf. wiederverwendeten) Coverbilds, oder null
 * bei jedem Fehlschlag — nie eine geworfene Exception, siehe Datei-Kommentar. */
export async function ensureCoverImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  input: CoverImageInput,
): Promise<string | null> {
  try {
    return await ensureCoverImageInner(supabase, input);
  } catch (err) {
    console.error(
      `ensureCoverImage failed for ${input.sourceUrl}: ${
        err instanceof Error ? err.message : String(err)
      }`,
    );
    return null;
  }
}

async function ensureCoverImageInner(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  input: CoverImageInput,
): Promise<string | null> {
  const { sourceUrl, originType, originId } = input;

  // 1. Exakte source_url für dasselbe Origin schon bekannt? Direkt
  // wiederverwenden, kein erneuter Download/keine erneute Verarbeitung.
  const { data: existingByUrl } = await supabase
    .from("images")
    .select("id, storage_path")
    .eq("origin_type", originType)
    .eq("origin_id", originId)
    .eq("source_url", sourceUrl)
    .maybeSingle();
  if (existingByUrl?.storage_path) return existingByUrl.id;

  let bytes: Uint8Array | null;
  let mimeTypeHint: string | null = null;
  if (input.sourceBytes) {
    bytes = input.sourceBytes;
  } else {
    const check = await checkImageUrl(sourceUrl);
    if (!check.reachable) return null;
    mimeTypeHint = check.contentType ?? null;
    bytes = await downloadImage(sourceUrl);
  }
  if (!bytes) return null;
  const contentHash = await sha256(bytes);

  const { data: existingByContentHash } = await supabase
    .from("images").select(
      "id, storage_path, thumbnail_path, width, height, mime_type, phash",
    ).eq("content_hash", contentHash)
    .not("storage_path", "is", null).limit(1).maybeSingle();
  if (existingByContentHash) {
    // Derselbe Blob darf wiederverwendet werden, die Provenienz-Zeile aber
    // nicht: origin_type/origin_id gehören immer zum aktuellen Datensatz.
    const { data: linked } = await supabase.from("images").insert({
      storage_path: existingByContentHash.storage_path,
      thumbnail_path: existingByContentHash.thumbnail_path,
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
    return linked?.id ?? null;
  }

  await ensureMagickReady();

  const decoded = decodeImage(bytes);
  if (!decoded) return null;
  const { width, height, webpBytes, thumbnailBytes, phash } = decoded;
  if (width < 400 || height < 300) return null;

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
  if (!isAcceptableImageDimensions(width, height)) return null;

  // 2. pHash-Dedupe: dieselbe Bilddatei schon für irgendein Origin
  // gespeichert (z.B. über eine andere source_url oder ein anderes Event
  // derselben Quelle)? Dann die bestehende Zeile wiederverwenden statt
  // erneut hochzuladen. Exakter Hash-Vergleich (siehe Migration), kein
  // Hamming-Distanz-Scan über alle Zeilen.
  const { data: existingByHash } = await supabase
    .from("images")
    .select("id, origin_type, origin_id")
    .eq("phash", phash)
    .not("storage_path", "is", null)
    .limit(1)
    .maybeSingle();
  if (existingByHash) {
    return existingByHash.origin_type === originType &&
        existingByHash.origin_id === originId
      ? existingByHash.id
      : null;
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
    return null;
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
    return null;
  }

  return inserted.id;
}

async function downloadImage(url: string): Promise<Uint8Array | null> {
  try {
    let current = url;
    let res: Response | null = null;
    for (let redirects = 0; redirects <= 4; redirects++) {
      if (!isPublicImageUrl(current)) return null;
      res = await fetch(current, {
        headers: { "User-Agent": USER_AGENT },
        redirect: "manual",
      });
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
    const buf = await res.arrayBuffer();
    if (buf.byteLength > MAX_IMAGE_BYTES) return null;
    return new Uint8Array(buf);
  } catch {
    return null;
  }
}

async function sha256(bytes: Uint8Array): Promise<string> {
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
}

/** Drei unabhängige ImageMagick.read()-Aufrufe statt einmal lesen + klonen:
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

    return {
      width: full.width,
      height: full.height,
      webpBytes: full.webpBytes,
      thumbnailBytes,
      phash,
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
