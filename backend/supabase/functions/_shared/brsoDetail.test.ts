import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseBrsoEventDetail } from "./brsoDetail.ts";

// Ausschnitt der echten Seite https://www.brso.de/konzerte/sir-simon-rattle-beethoven-9/
// (abgerufen 2026-08-14), auf das Nötige gekürzt.
const REAL_PAGE_EXCERPT = `
<meta property="og:image" content="https://www.brso.de/wp-content/uploads/sites/2/16-9-simon-rattle-c-br-astrid-ackermann.jpg" />
...
<div class="w-full mb-6 md:mb-12 last:mb-0">
  <h3 class="h3">Mitwirkende</h3>
</div>
<div class="w-full mb-12 last:mb-0">
  <div class="mb-12 last:mb-0">
    <div class="mb-1.5 last:mb-0">
      <span class="font-bold">
        Sir Simon Rattle </span>
      <span>
        Dirigent </span>
    </div>
    <div class="mb-1.5 last:mb-0">
      <span class="font-bold">
        Lucy Crowe </span>
      <span>
        Sopran </span>
    </div>
    <div class="mb-1.5 last:mb-0">
      <span class="font-bold">
        Chor des Bayerischen Rundfunks </span>
    </div>
    <div class="mb-1.5 last:mb-0">
      <span class="font-bold">
        Symphonieorchester des Bayerischen Rundfunks </span>
    </div>
  </div>
</div>
</section>
<section class="section section--s-logos">
<div class="mb-1.5 last:mb-0"><span class="font-bold">Sollte nicht mehr geparst werden</span></div>
`;

Deno.test("parseBrsoEventDetail extracts og:image and classifies participants by span count", () => {
  const detail = parseBrsoEventDetail(REAL_PAGE_EXCERPT);
  assertEquals(detail.imageUrl, "https://www.brso.de/wp-content/uploads/sites/2/16-9-simon-rattle-c-br-astrid-ackermann.jpg");
  assertEquals(detail.participants, [
    { name: "Sir Simon Rattle", profileUrl: null, role: "dirigent", type: "person" },
    { name: "Lucy Crowe", profileUrl: null, role: "solist", type: "person" },
    { name: "Chor des Bayerischen Rundfunks", profileUrl: null, role: null, type: "ensemble" },
    { name: "Symphonieorchester des Bayerischen Rundfunks", profileUrl: null, role: null, type: "ensemble" },
  ]);
});

Deno.test("parseBrsoEventDetail stops at the next <section> and does not read past the cast list", () => {
  const detail = parseBrsoEventDetail(REAL_PAGE_EXCERPT);
  assertEquals(detail.participants.some((p) => p.name === "Sollte nicht mehr geparst werden"), false);
});

Deno.test("parseBrsoEventDetail classifies a choir-leader role", () => {
  const html = `
<h3 class="h3">Mitwirkende</h3>
<div class="mb-1.5 last:mb-0"><span class="font-bold">Peter Dijkstra</span><span>Chorleitung</span></div>
<section>`;
  assertEquals(parseBrsoEventDetail(html).participants, [
    { name: "Peter Dijkstra", profileUrl: null, role: "chorleiter", type: "person" },
  ]);
});

Deno.test("parseBrsoEventDetail returns empty participants and null image without a match", () => {
  const detail = parseBrsoEventDetail("<html><body>Kein passendes Markup.</body></html>");
  assertEquals(detail.imageUrl, null);
  assertEquals(detail.participants, []);
});

// Live-Fund (br-chor.de, dieselbe Seitenvorlage wie brso.de): kein eigenes
// og:image pro Termin (überall dasselbe Site-Logo), Rolle "Leitung" statt
// "Dirigent" — beide Fälle wurden vorher falsch behandelt.
Deno.test("parseBrsoEventDetail rejects a site-wide generic logo as the event image", () => {
  const html = `<meta property="og:image" content="https://www.br-chor.de/wp-content/uploads/sites/4/br-chor-logo-socials.png" />`;
  assertEquals(parseBrsoEventDetail(html).imageUrl, null);
});

Deno.test("parseBrsoEventDetail classifies \"Leitung\" as dirigent (br-chor.de wording)", () => {
  const html = `
<h3 class="h3">Mitwirkende</h3>
<div class="mb-1.5 last:mb-0"><span class="font-medium">Giovanni Antonini</span><span>Leitung</span></div>
<section>`;
  assertEquals(parseBrsoEventDetail(html).participants, [
    { name: "Giovanni Antonini", profileUrl: null, role: "dirigent", type: "person" },
  ]);
});
