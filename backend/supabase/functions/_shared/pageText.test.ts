import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { stripRelatedSections } from "./pageText.ts";

const program = "Andrea Marcon\nConductor\nWolfgang Amadeus Mozart\nOverture to »Così fan tutte«\nCarl Maria von Weber\nConcerto for Bassoon in F major\n".repeat(3);

Deno.test("stripRelatedSections schneidet das 'Further Events'-Karussell ab", () => {
  const text = `${program}Further Events\n10 Oct 2026\nHanni Liang\nPiano\nNexus`;
  assertEquals(stripRelatedSections(text), program.trimEnd());
});

Deno.test("stripRelatedSections erkennt auch deutsche Überschriften", () => {
  const text = `${program}Weitere Veranstaltungen\nZubin Mehta\nDirigent`;
  assertEquals(stripRelatedSections(text), program.trimEnd());
});

Deno.test("stripRelatedSections lässt gleichnamige Navigationspunkte am Seitenanfang unberührt", () => {
  const text = `Further Events\n${program}`;
  assertEquals(stripRelatedSections(text), text);
});

Deno.test("stripRelatedSections ändert Text ohne Empfehlungsbereich nicht", () => {
  assertEquals(stripRelatedSections(program), program);
});
