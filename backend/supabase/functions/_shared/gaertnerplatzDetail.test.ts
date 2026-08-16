import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseGaertnerplatzEventDetail } from "./gaertnerplatzDetail.ts";

// Ausschnitt der echten Seite https://www.gaertnerplatztheater.de/de/
// produktionen/la-traviata.html (abgerufen 2026-08-15/16), auf das
// Nötige gekürzt.
const REAL_PAGE_EXCERPT = `
<div id="besetzungBox" class="my-10 my-xl-5 no-hyphens">
  <h2 class="fs-4 mb-3 text-start">Besetzung</h2>
  <div id="regieteam">
    <div class="function_person">
      <span class="function d-block d-xl-inline">Dirigat</span>
      <span class="person d-block d-xl-inline fw-bold">
        <a title="Rubén Dubrovsky" class="text-font-color" href="personen/ruben-dubrovsky.html">Rubén Dubrovsky</a></span>
    </div>
    <div class="function_person">
      <span class="function d-block d-xl-inline">Regie</span>
      <span class="person d-block d-xl-inline fw-bold">
        <a title="Isabel Ostermann" class="text-font-color" href="personen/isabel-ostermann.html">Isabel Ostermann</a></span>
    </div>
    <br />
    <div class="function_person">
      <span class="function d-block d-xl-inline">Violetta Valéry</span>
      <span class="person d-block d-xl-inline fw-bold">
        <a title="Jennifer O’Loughlin" class="text-font-color" href="personen/jennifer-oloughlin.html">Jennifer O’Loughlin</a></span>
    </div>
    <div class="function_person">
      <span class="function d-block d-xl-inline">Diener bei Flora</span>
      <span class="person d-block d-xl-inline fw-bold">
        Aran Matsuda</span>
    </div>
  </div>
  <br />
  <p>
    <b>Chor, Statisterie und Kinderstatisterie des Staatstheaters am Gärtnerplatz</b>
    <br>
    <b>Orchester des Staatstheaters am Gärtnerplatz</b>
  </p>
</div>
<div id="termineBox"><p><b>Sollte nicht mehr geparst werden</b></p></div>
`;

Deno.test("parseGaertnerplatzEventDetail extracts performers with resolved bio links, drops the creative team, and adds house ensembles", () => {
  const detail = parseGaertnerplatzEventDetail(REAL_PAGE_EXCERPT);
  assertEquals(detail.participants, [
    { name: "Rubén Dubrovsky", profileUrl: "https://www.gaertnerplatztheater.de/de/personen/ruben-dubrovsky.html", role: "dirigent", type: "person" },
    { name: "Jennifer O’Loughlin", profileUrl: "https://www.gaertnerplatztheater.de/de/personen/jennifer-oloughlin.html", role: "solist", type: "person" },
    { name: "Aran Matsuda", profileUrl: null, role: "solist", type: "person" },
    { name: "Chor, Statisterie und Kinderstatisterie des Staatstheaters am Gärtnerplatz", profileUrl: null, role: null, type: "ensemble" },
    { name: "Orchester des Staatstheaters am Gärtnerplatz", profileUrl: null, role: null, type: "ensemble" },
  ]);
});

Deno.test("parseGaertnerplatzEventDetail stops at termineBox and does not read past the cast section", () => {
  const detail = parseGaertnerplatzEventDetail(REAL_PAGE_EXCERPT);
  assertEquals(detail.participants.some((p) => p.name === "Sollte nicht mehr geparst werden"), false);
});

Deno.test("parseGaertnerplatzEventDetail returns no participants without a besetzungBox", () => {
  assertEquals(parseGaertnerplatzEventDetail("<html><body>Kein passendes Markup.</body></html>").participants, []);
});
