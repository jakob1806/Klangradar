import { assertEquals } from "jsr:@std/assert@1";
import { germanizeWorkTitle } from "./workTitleGerman.ts";

Deno.test("germanizeWorkTitle: typische mphil.de-Titel", () => {
  assertEquals(germanizeWorkTitle("Concerto for Violin and Orchestra No. 1 in A minor, Opus 77"), "Konzert für Violine und Orchester Nr. 1 a-Moll, op. 77");
  assertEquals(germanizeWorkTitle("Symphony No. 39 in G minor Hob. I:39"), "Sinfonie Nr. 39 g-Moll Hob. I:39");
  assertEquals(germanizeWorkTitle("Concerto for Piano (Left Hand) and Orchestra in D major"), "Konzert für Klavier (linke Hand) und Orchester D-Dur");
  assertEquals(germanizeWorkTitle("Overture to »The Sea Hawk«"), "Ouvertüre zu »The Sea Hawk«");
  assertEquals(germanizeWorkTitle("Symphony No. 4 in E-flat major »Romantic«"), "Sinfonie Nr. 4 Es-Dur »Romantic«");
  assertEquals(germanizeWorkTitle("Konzert für Violine und Orchester Nr. 1"), "Konzert für Violine und Orchester Nr. 1");
});
