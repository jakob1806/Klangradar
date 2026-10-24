import { assertEquals } from "jsr:@std/assert@1";
import { candidateTitles, cleanIntro } from "./workWikiFacts.ts";

Deno.test("candidateTitles: Sinfonie und Konzert", () => {
  assertEquals(candidateTitles("Sinfonie Nr. 4 Es-Dur", "Anton Bruckner")[0], { lang: "de", title: "4. Sinfonie (Bruckner)" });
  assertEquals(candidateTitles("Konzert für Violine und Orchester Nr. 1", "Dmitri Schostakowitsch")[0], { lang: "de", title: "1. Violinkonzert (Schostakowitsch)" });
});

Deno.test("cleanIntro: kein Schnitt nach Zahl/Abkürzung", () => {
  const intro = cleanIntro("Die 9. Sinfonie in d-Moll op. 125 ist die letzte Sinfonie von Beethoven. Sie wurde 1824 uraufgeführt.");
  assertEquals(intro, "Die 9. Sinfonie in d-Moll op. 125 ist die letzte Sinfonie von Beethoven. Sie wurde 1824 uraufgeführt.");
});
