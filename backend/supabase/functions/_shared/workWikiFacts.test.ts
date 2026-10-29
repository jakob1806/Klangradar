// Erstellt von Claude Code (29.10.2026): Werkverzeichnis-Abgleich der
// Werkeinführungen (Wikidata-Treffer, Schutz vor falschem Werk).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { catalogConflict, catalogKeys, normalizeWorkTitle } from "./workWikiFacts.ts";

Deno.test("catalogKeys vereinheitlicht Werkverzeichnisse", () => {
  assertEquals(catalogKeys("KV 620"), ["kv620"]);
  assertEquals(catalogKeys("Symphonie Nr. 4 B-Dur op. 60"), ["op60"]);
  assertEquals(catalogKeys("K. 388"), ["kv388"]);
  assertEquals(catalogKeys("D 759"), ["d759"]);
  assertEquals(catalogKeys("op. 18 Nr. 1"), ["op18/1"]);
});

Deno.test("catalogConflict verwirft Artikel zu einem anderen Werk", () => {
  assert(catalogConflict("Die Sinfonie g-Moll KV 550 komponierte Mozart 1788.", "Symphonie g-Moll, KV 183", null));
  assert(!catalogConflict("Die Zauberflöte (KV 620) ist eine Oper.", "Ouvertüre aus Die Zauberflöte", "KV 620"));
  assert(!catalogConflict("Eine Oper ohne Nummer.", "Ouvertüre", "KV 620"));
});

Deno.test("normalizeWorkTitle glättet HTML-Entities", () => {
  assertEquals(normalizeWorkTitle("Symphonie (&quot;Classique&quot;)"), 'Symphonie ("Classique")');
});
