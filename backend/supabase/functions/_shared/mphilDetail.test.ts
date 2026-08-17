import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseMphilEventDetail } from "./mphilDetail.ts";

// Ausschnitt der echten Seite https://www.mphil.de/en/concerts-tickets/
// calendar/concerts/brahms-schostakowitsch-2026-08-30-21-00-00
// (abgerufen 2026-08-14), auf das Nötige gekürzt.
const REAL_PAGE_EXCERPT = `
<li class="m-mphil-concertlist__person -soloist">
  <span class="m-mphil-concertlist__instrument">Conductor</span>
  <button class="m-mphil-concertlist__person-link --wrap" aria-controls="person-59766-0-0"><span class="m-mphil-concertlist__person-link-title">Lahav Shani</span>
  </button>
  <div class="l-modal m-mphil-concertlist__modal -width-8" id="person-59766-0-0" data-modal>
    <div class="l-container -width-12">
      <div class="l-container__inner">
        <h2>Lahav Shani</h2>
        <p>Der 1989 in Tel Aviv geborene Lahav Shani studierte...</p>
        <p><a class="e-button-primary" href="/en/ueber-uns/musicians/details/lahav-shani">more</a></p>
      </div>
    </div>
  </div>
</li>
<li class="m-mphil-concertlist__person -soloist">
  <span class="m-mphil-concertlist__instrument">Violin</span>
  <button class="m-mphil-concertlist__person-link --wrap" aria-controls="person-1-0-0"><span class="m-mphil-concertlist__person-link-title">Julia Fischer</span>
  </button>
  <div class="l-modal m-mphil-concertlist__modal -width-8" id="person-1-0-0" data-modal>
    <div class="l-container -width-12">
      <div class="l-container__inner">
        <h2>Julia Fischer</h2>
        <p><a class="e-button-primary" href="/en/ueber-uns/musicians/details/julia-fischer">more</a></p>
      </div>
    </div>
  </div>
</li>
`;

Deno.test("parseMphilEventDetail extracts participants with resolved bio links and adds the resident ensemble", () => {
  const detail = parseMphilEventDetail(REAL_PAGE_EXCERPT, "https://www.mphil.de/en/concerts-tickets/calendar/concerts/brahms-schostakowitsch-2026-08-30-21-00-00");
  assertEquals(detail.participants, [
    { name: "Lahav Shani", profileUrl: "https://www.mphil.de/en/ueber-uns/musicians/details/lahav-shani", role: "dirigent", type: "person" },
    { name: "Julia Fischer", profileUrl: "https://www.mphil.de/en/ueber-uns/musicians/details/julia-fischer", role: "solist", type: "person" },
    { name: "Münchner Philharmoniker", profileUrl: null, role: null, type: "ensemble" },
  ]);
});

Deno.test("parseMphilEventDetail returns no participants (and no resident ensemble) when the page has no cast list", () => {
  const detail = parseMphilEventDetail("<html><body>Kein passendes Markup.</body></html>", "https://www.mphil.de/");
  assertEquals(detail.participants, []);
});

// Live-Fund (2026-08-14, Event "brahms-adams-beethoven-2026-08-31-19-30-00"):
// Gastensembles stehen im selben Listen-Markup wie Personen, aber OHNE
// <span class="...__instrument">-Rolle — ohne Sonderbehandlung landete
// "Philharmonischer Chor München" fälschlich als Person in der Datenbank.
Deno.test("parseMphilEventDetail classifies a person-list entry without a role span as an ensemble", () => {
  const html = `
<li class="m-mphil-concertlist__person -soloist">
  <button class="m-mphil-concertlist__person-link --wrap" aria-controls="person-59771-4-2"><span class="m-mphil-concertlist__person-link-title">Philharmonischer Chor München</span>
  </button>
  <div class="l-modal m-mphil-concertlist__modal -width-8" id="person-59771-4-2" data-modal>
    <div class="l-container -width-12">
      <div class="l-container__inner">
        <h2>Philharmonischer Chor München</h2>
      </div>
    </div>
  </div>
</li>`;
  const detail = parseMphilEventDetail(html, "https://www.mphil.de/en/concerts-tickets/calendar/concerts/brahms-adams-beethoven-2026-08-31-19-30-00");
  assertEquals(detail.participants, [
    { name: "Philharmonischer Chor München", profileUrl: null, role: null, type: "ensemble" },
    { name: "Münchner Philharmoniker", profileUrl: null, role: null, type: "ensemble" },
  ]);
});
