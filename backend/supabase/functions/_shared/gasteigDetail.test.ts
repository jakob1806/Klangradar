import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseGasteigEventDetail } from "./gasteigDetail.ts";

// Ausschnitt der echten Seite https://www.gasteig.de/veranstaltungen/
// lucerne-festival-contemporary-orchestra-mit-joerg-widmann/
// (abgerufen 2026-08-14).
const REAL_PAGE_EXCERPT = `
<h2>Programm</h2><ul><li>Werk XY</li></ul>
<h2>Mitwirkende</h2><ul><li>Michael Engelhardt, Sprecher</li><li>N.N. Schlagzeuggruppe</li><li>Christoph Sietzen, Schlagzeug und Einstudierung</li><li>Markus Güdel, Licht</li><li>Maxime Le Saux, Klangregie</li><li>Lucerne Festival Contemporary Orchestra</li><li>Jörg Widmann, Leitung</li></ul>
<p>Eine Veranstaltung der <em>musica viva</em> des Bayerischen Rundfunks</p>
`;

Deno.test("parseGasteigEventDetail extracts performers, classifies roles, and drops technical credits/placeholders", () => {
  const detail = parseGasteigEventDetail(REAL_PAGE_EXCERPT);
  assertEquals(detail.participants, [
    { name: "Michael Engelhardt", profileUrl: null, role: "solist", type: "person" },
    { name: "Christoph Sietzen", profileUrl: null, role: "solist", type: "person" },
    { name: "Lucerne Festival Contemporary Orchestra", profileUrl: null, role: null, type: "ensemble" },
    { name: "Jörg Widmann", profileUrl: null, role: "dirigent", type: "person" },
  ]);
});

Deno.test("parseGasteigEventDetail returns no participants without a Mitwirkende section", () => {
  assertEquals(parseGasteigEventDetail("<html><body>Kein passendes Markup.</body></html>").participants, []);
});
