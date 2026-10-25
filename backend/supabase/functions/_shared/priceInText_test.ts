import { assertEquals } from "jsr:@std/assert@1";
import { splitPriceInfo } from "./priceInText.ts";

Deno.test("splitPriceInfo: Staatsoper-Preiszeile", () => {
  const r = splitPriceInfo("Laurent Hilaire. Musik Adolphe Adam Preise H , € 88 / 77 / 63 / 50 / 35 / 23 / 11 / 8 Abo-Geschenk-Abo IV");
  assertEquals(r.description, "Laurent Hilaire. Musik Adolphe Adam");
  assertEquals([r.priceMin, r.priceMax], [8, 88]);
});

Deno.test("splitPriceInfo: nur Platzhalter", () => {
  const r = splitPriceInfo("Wolfgang Amadeus Mozart Preise K , € - /- /- /- /- /- /- /10 <30");
  assertEquals(r.description, "Wolfgang Amadeus Mozart");
  assertEquals(r.priceMax, 10);
});

Deno.test("splitPriceInfo: Text ohne Preise bleibt", () => {
  assertEquals(splitPriceInfo("Ein Abend mit Mozart.").description, "Ein Abend mit Mozart.");
});
