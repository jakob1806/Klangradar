// Erster Deno-Test im Repo (Abschnitt 9 der Gesamtüberarbeitung: "Tests für
// Bild-Validierung"). Testet nur isAcceptableImageDimensions() — die reine,
// aus ensureCoverImage() extrahierte Prüf-Funktion; ensureCoverImage() selbst
// braucht einen echten Supabase-Client/Storage/ImageMagick-WASM und ist damit
// kein sinnvoller Kandidat für einen isolierten Unit-Test.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { computeSharpnessVariance, isAcceptableImageDimensions } from "./imagePipeline.ts";

Deno.test("rejects images below the minimum resolution", () => {
  assertEquals(isAcceptableImageDimensions(639, 480), false);
  assertEquals(isAcceptableImageDimensions(640, 479), false);
  assertEquals(isAcceptableImageDimensions(300, 200), false);
});

Deno.test("accepts a typical landscape press photo", () => {
  assertEquals(isAcceptableImageDimensions(1600, 900), true); // 16:9
  assertEquals(isAcceptableImageDimensions(1200, 800), true); // 3:2
});

Deno.test("accepts a typical portrait photo", () => {
  assertEquals(isAcceptableImageDimensions(800, 1067), true); // 3:4
});

Deno.test("rejects an extreme wide banner even at sufficient resolution", () => {
  // 2400x480 erfüllt beide Mindestmaße einzeln, ist aber ein Werbe-Banner,
  // kein Foto (Seitenverhältnis 5:1).
  assertEquals(isAcceptableImageDimensions(2400, 480), false);
});

Deno.test("rejects an extreme tall sidebar graphic even at sufficient resolution", () => {
  assertEquals(isAcceptableImageDimensions(640, 2400), false);
});

Deno.test("accepts the exact boundary aspect ratios", () => {
  assertEquals(isAcceptableImageDimensions(640, 1600), true); // genau 0.4
  assertEquals(isAcceptableImageDimensions(1920, 640), true); // genau 3.0
});

Deno.test("rejects just outside the boundary aspect ratios", () => {
  assertEquals(isAcceptableImageDimensions(640, 1601), false);
  assertEquals(isAcceptableImageDimensions(1921, 640), false);
});

// computeSharpnessVariance() — Laplacian-Varianz als Schärfe-Maß (Nutzerwunsch:
// "Schärfe-Heuristik ... um unscharfe/verpixelte Treffer vor der Freigabe
// auszusortieren"). Getestet mit synthetischen Graustufen-Arrays statt echten
// Bildern — reine Funktion, kein ImageMagick/WASM nötig.
function flatImage(size: number, value = 128): Uint8Array {
  return new Uint8Array(size * size).fill(value);
}

function checkerboardImage(size: number): Uint8Array {
  const gray = new Uint8Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      gray[y * size + x] = (x + y) % 2 === 0 ? 0 : 255;
    }
  }
  return gray;
}

function smoothGradientImage(size: number): Uint8Array {
  const gray = new Uint8Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      gray[y * size + x] = Math.round((x / (size - 1)) * 255);
    }
  }
  return gray;
}

Deno.test("computeSharpnessVariance: a perfectly flat image has zero variance (no edges)", () => {
  assertEquals(computeSharpnessVariance(flatImage(32), 32, 32), 0);
});

Deno.test("computeSharpnessVariance: a high-contrast checkerboard scores far higher than a smooth gradient", () => {
  const sharp = computeSharpnessVariance(checkerboardImage(32), 32, 32);
  const blurry = computeSharpnessVariance(smoothGradientImage(32), 32, 32);
  assert(sharp > blurry * 100, `expected checkerboard (${sharp}) to be far sharper than gradient (${blurry})`);
});

Deno.test("computeSharpnessVariance: degenerate tiny images return 0 instead of throwing", () => {
  assertEquals(computeSharpnessVariance(new Uint8Array(4), 2, 2), 0);
  assertEquals(computeSharpnessVariance(new Uint8Array(0), 0, 0), 0);
});
