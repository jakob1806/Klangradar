// Erster Deno-Test im Repo (Abschnitt 9 der Gesamtüberarbeitung: "Tests für
// Bild-Validierung"). Testet nur isAcceptableImageDimensions() — die reine,
// aus ensureCoverImage() extrahierte Prüf-Funktion; ensureCoverImage() selbst
// braucht einen echten Supabase-Client/Storage/ImageMagick-WASM und ist damit
// kein sinnvoller Kandidat für einen isolierten Unit-Test.
import { assertEquals } from "jsr:@std/assert@1";
import { isAcceptableImageDimensions } from "./imagePipeline.ts";

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
