import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseMphilEventDetail } from "./mphilDetail.ts";

// Ausschnitt der echten Seite https://www.mphil.de/en/concerts-tickets/
// calendar/concerts/zemlinsky-mozart-mendelssohn-bartholdy-2026-09-25-19-30-00
// (abgerufen 2026-09-23, nach dem Website-Relaunch), auf das Nötige gekürzt.
const REAL_PAGE_EXCERPT = `
<ul class="m-mphil-concert-detail__person-list">
  <li class="m-mphil-concert-detail__person">
    <a class="m-mphil-concert-detail__person-link --wrap" href="/en/ueber-uns/musicians/details/ryan-bancroft">
      <span class="m-mphil-concert-detail__person-link-title">Ryan Bancroft</span>
    </a>
    <span class="m-mphil-concert-detail__instrument">
      <span class="nonbold small">Conductor
</span>
    </span>
  </li>
  <li class="m-mphil-concert-detail__person">
    <a class="m-mphil-concert-detail__person-link --wrap" href="/en/ueber-uns/musicians/details/emanuel-ax">
      <span class="m-mphil-concert-detail__person-link-title">Emanuel Ax</span>
    </a>
    <span class="m-mphil-concert-detail__instrument">
      <span class="nonbold small">Piano
</span>
    </span>
  </li>
</ul>
<!-- "Weitere Veranstaltungen"-Karussell am Seitenende: zeigt die Besetzung
     ANDERER, unverwandter Konzerte im alten "m-mphil-concertlist__person"-
     Markup. Musste vorher fälschlich mitgeparst werden (Live-Fund
     2026-09-23) — darf hier NICHT in den Treffern landen. -->
<li class="m-mphil-concertlist__person -soloist">
  <span class="m-mphil-concertlist__instrument">Piano</span>
  <p class="m-mphil-concertlist__person-link -inactive">Hanni Liang</p>
</li>
`;

Deno.test("parseMphilEventDetail extracts participants with resolved bio links and adds the resident ensemble", () => {
  const detail = parseMphilEventDetail(
    REAL_PAGE_EXCERPT,
    "https://www.mphil.de/en/concerts-tickets/calendar/concerts/zemlinsky-mozart-mendelssohn-bartholdy-2026-09-25-19-30-00",
  );
  assertEquals(detail.participants, [
    { name: "Ryan Bancroft", profileUrl: "https://www.mphil.de/en/ueber-uns/musicians/details/ryan-bancroft", role: "dirigent", type: "person" },
    { name: "Emanuel Ax", profileUrl: "https://www.mphil.de/en/ueber-uns/musicians/details/emanuel-ax", role: "solist", type: "person" },
    { name: "Münchner Philharmoniker", profileUrl: null, role: null, type: "ensemble" },
  ]);
});

Deno.test("parseMphilEventDetail returns no participants (and no resident ensemble) when the page has no cast list", () => {
  const detail = parseMphilEventDetail("<html><body>Kein passendes Markup.</body></html>", "https://www.mphil.de/");
  assertEquals(detail.participants, []);
});

// Live-Fund (2026-09-23, Event "nexus-2026-10-10"): Gastensembles ohne
// individuelle Rolle stehen im selben <li>-Markup wie Solist:innen, aber mit
// leerem <span class="...__instrument">-Eintrag statt einem verschachtelten
// <span class="nonbold small">-Rolle. Ohne diese Unterscheidung landet ein
// Ensemble fälschlich als Person in der Datenbank. Namen ohne Bio-Link stehen
// hier zudem in einem <p -inactive> statt in <a>+<span ...-title>.
Deno.test("parseMphilEventDetail classifies a person-list entry without a role as an ensemble, and reads names without a bio link from the plain <p>", () => {
  const html = `
<li class="m-mphil-concert-detail__person">
  <p class="m-mphil-concert-detail__person-link -inactive">Hanni Liang</p>
  <span class="m-mphil-concert-detail__instrument">
    <span class="nonbold small">Piano</span>
  </span>
</li>
<li class="m-mphil-concert-detail__person">
  <p class="m-mphil-concert-detail__person-link -inactive"> Mitglieder der Münchner Philharmoniker</p>
  <span class="m-mphil-concert-detail__instrument">
  </span>
</li>`;
  const detail = parseMphilEventDetail(html, "https://www.mphil.de/en/concerts-tickets/calendar/concerts/nexus-2026-10-10");
  assertEquals(detail.participants, [
    { name: "Hanni Liang", profileUrl: null, role: "solist", type: "person" },
    { name: "Mitglieder der Münchner Philharmoniker", profileUrl: null, role: null, type: "ensemble" },
    { name: "Münchner Philharmoniker", profileUrl: null, role: null, type: "ensemble" },
  ]);
});
