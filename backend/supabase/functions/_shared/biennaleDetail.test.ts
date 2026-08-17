import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseBiennaleEventDetail } from "./biennaleDetail.ts";

// Ausschnitt der echten Seite https://www.muenchener-biennale.de/en/
// programm/kalender/crypt (abgerufen 2026-08-16), auf das Nötige gekürzt.
const REAL_PAGE_EXCERPT = `
<div class="info"><span class="label t5"><p>Composition, text:</p></span><span>&nbsp;</span><span class="artist bold t5">YURI UMEMOTO</span></div>
<div class="info"><span class="label t5"><p>Musical direction:</p></span><span>&nbsp;</span><span class="artist bold t5">CHRISTIAN EGGEN</span></div>
<div class="info"><span class="label t5"><p>Costume design:</p></span><span>&nbsp;</span><span class="artist bold t5">INGRID TORVUND</span></div>
<div class="info"><span class="label t5"><p>Soprano:</p></span><span>&nbsp;</span><span class="artist bold t5">PEYEE CHEN</span></div>
<div class="info"><span class="label t5"><p>Violin:</p></span><span>&nbsp;</span><span class="artist bold t5">KARIN HELLQVIST</span><span class="bold sep t5">,</span><span>&nbsp;</span><span class="artist bold t5">EMILIE LIDSHEIM</span></div>
<div class="info"><span class="label t5"></span><span class="artist bold t5">OSLO SINFONIETTA</span></div>
`;

Deno.test("parseBiennaleEventDetail extracts performers, drops the creative team, handles multi-name roles and empty-label ensembles", () => {
  const detail = parseBiennaleEventDetail(REAL_PAGE_EXCERPT);
  assertEquals(detail.participants, [
    { name: "CHRISTIAN EGGEN", profileUrl: null, role: "dirigent", type: "person" },
    { name: "PEYEE CHEN", profileUrl: null, role: "solist", type: "person" },
    { name: "KARIN HELLQVIST", profileUrl: null, role: "solist", type: "person" },
    { name: "EMILIE LIDSHEIM", profileUrl: null, role: "solist", type: "person" },
    { name: "OSLO SINFONIETTA", profileUrl: null, role: null, type: "ensemble" },
  ]);
});

Deno.test("parseBiennaleEventDetail returns no participants without info blocks", () => {
  assertEquals(parseBiennaleEventDetail("<html><body>Kein passendes Markup.</body></html>").participants, []);
});
