// Regressionstest für einen live bestätigten Datenkorruptions-Bug:
// img.write(MagickFormat.WebP, (data) => data) lieferte bisher eine reine
// Sicht auf WASM-Linearspeicher zurück statt einer Kopie — der NÄCHSTE
// ImageMagick.read()-Aufruf (Thumbnail, danach pHash) überschrieb diesen
// Speicher, bevor die zuerst erzeugten webpBytes tatsächlich hochgeladen
// wurden. Ergebnis live in Supabase Storage bestätigt: weder storage_path
// noch thumbnail_path enthielten gültige WebP-Dateien (falsche Magic
// Bytes), und storage_path/thumbnail_path derselben Zeile waren
// bytidentisch — beide zeigten denselben zuletzt überschriebenen
// Speicherbereich. Fix: .slice() im write()-Callback kopiert die Bytes,
// bevor der nächste Magick-Aufruf den Speicher wiederverwendet.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { decodeImage, ensureMagickReady } from "./imagePipeline.ts";

// Minimales gültiges 1x1-Pixel-PNG (rot) — kein Netzwerkzugriff nötig.
const ONE_PIXEL_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

function decodePng(): Uint8Array {
  const binary = atob(ONE_PIXEL_PNG_BASE64);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

function isValidRiffWebp(bytes: Uint8Array): boolean {
  // "RIFF" Magic Bytes — jede gültige WebP-Datei beginnt damit.
  return bytes.length >= 4 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
    bytes[2] === 0x46 && bytes[3] === 0x46;
}

await ensureMagickReady();

Deno.test("decodeImage: full-size webpBytes survive later ImageMagick calls (WASM-Aliasing-Regression)", () => {
  const decoded = decodeImage(decodePng());
  assert(decoded, "decodeImage sollte für ein gültiges PNG nicht null liefern");
  assert(
    isValidRiffWebp(decoded.webpBytes),
    `webpBytes sollten mit RIFF beginnen, waren aber: ${Array.from(decoded.webpBytes.slice(0, 4))}`,
  );
});

Deno.test("decodeImage: thumbnail is a valid WebP too", () => {
  const decoded = decodeImage(decodePng());
  assert(decoded);
  assert(
    isValidRiffWebp(decoded.thumbnailBytes),
    `thumbnailBytes sollten mit RIFF beginnen, waren aber: ${Array.from(decoded.thumbnailBytes.slice(0, 4))}`,
  );
});

Deno.test("decodeImage: full and thumbnail bytes are genuinely different buffers, not aliased WASM memory", () => {
  const decoded = decodeImage(decodePng());
  assert(decoded);
  const aliased = decoded.webpBytes.length === decoded.thumbnailBytes.length &&
    decoded.webpBytes.every((b, i) => b === decoded.thumbnailBytes[i]);
  assertEquals(aliased, false, "full- und thumbnail-Bytes dürfen nicht identisch/aliasiert sein");
});
