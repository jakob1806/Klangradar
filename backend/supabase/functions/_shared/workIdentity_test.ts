import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { catalogKey, numberedKey, sameWork, workIdentity } from "./workIdentity.ts";

const same = (a: string, b: string, ca?: string, cb?: string) => sameWork(workIdentity(a, ca), workIdentity(b, cb));

Deno.test("Sinfonie-Varianten sind dasselbe Werk", () => {
  assert(same("5. Sinfonie", "Sinfonie Nr. 5 cis-Moll"));
  assert(same("Symphonie Nr. 5 in cis-Moll", "Symphony No. 5"));
  assert(same("Sinfonie Nr. 4 e-Moll op. 98", "4. Sinfonie"));
  assert(same("4. Symphonie", "Sinfonie Nr. 4 e-Moll"));
});

Deno.test("Konzert-Varianten", () => {
  assert(same("Klavierkonzert Nr. 2", "Konzert für Klavier und Orchester Nr. 2 B-Dur op. 83"));
  assert(same("Violinkonzert D-Dur op. 61", "Konzert für Violine und Orchester D-Dur op. 61"));
});

Deno.test("Werkverzeichnis entscheidet", () => {
  assert(same("Matthäus-Passion", "Matthäus-Passion BWV 244", "BWV 244"));
  assert(same("Eine kleine Nachtmusik KV 525", "Serenade G-Dur K. 525"));
  assertFalse(same("Klaviersonate Nr. 8 c-Moll op. 13", "Klaviersonate op. 27 Nr. 2"));
  assertEquals(catalogKey("Klaviersonate op. 27 Nr. 2"), "op 27 nr 2");
});

Deno.test("Beinamen und Anführungszeichen", () => {
  assert(same("Sinfonie Nr. 3 „Eroica“", "Symphonie Nr. 3 Es-Dur (Eroica)"));
  assert(same("Ouvertüre zu »Ein Sommernachtstraum«", "Ouvertüre zu Ein Sommernachtstraum"));
});

Deno.test("Verschiedene Werke bleiben getrennt", () => {
  assertFalse(same("Sinfonie Nr. 5", "Sinfonie Nr. 6"));
  assertFalse(same("Klavierkonzert Nr. 1", "Violinkonzert Nr. 1"));
  assertFalse(same("Ein Heldenleben", "Also sprach Zarathustra"));
  assertEquals(numberedKey("D-Dur Serenade"), null);
  assertEquals(catalogKey("Sinfonie D-Dur"), null);
});
