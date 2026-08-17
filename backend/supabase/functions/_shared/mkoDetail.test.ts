import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseMkoEventDetail } from "./mkoDetail.ts";

// Ausschnitt der echten Seite https://www.m-k-o.eu/event-detail/2673/
// 26---27%20Abo%202/ (abgerufen 2026-08-14).
const REAL_PAGE_EXCERPT = `
<h4 class="text-transform-none hide-on-mobile"><b>12.11.2026, 20 Uhr Prinzregententheater</b></h4>
<p>Sarah Aristidou, Sopran<br>Bas Wiegers, Dirigent</p>
<h4 class="text-transform-none"><b>Programm</b></h4>
<p>Claude Debussy,<br> Petite Suite (Orchestrierung Henri Büsser)</p>
`;

Deno.test("parseMkoEventDetail extracts performers and adds the resident ensemble", () => {
  const detail = parseMkoEventDetail(REAL_PAGE_EXCERPT);
  assertEquals(detail.participants, [
    { name: "Sarah Aristidou", profileUrl: null, role: "solist", type: "person" },
    { name: "Bas Wiegers", profileUrl: null, role: "dirigent", type: "person" },
    { name: "Münchener Kammerorchester", profileUrl: null, role: null, type: "ensemble" },
  ]);
});

Deno.test("parseMkoEventDetail returns no participants (and no resident ensemble) without a Programm heading", () => {
  assertEquals(parseMkoEventDetail("<html><body>Kein passendes Markup.</body></html>").participants, []);
});
