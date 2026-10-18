import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseScrape } from "./scrape.ts";

const WEEKDAYS = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
const pad = (n: number) => n.toString().padStart(2, "0");

function listing(dates: Date[]): string {
  const items = dates.map((d, i) =>
    `<li class="ev"><span class="d">${WEEKDAYS[d.getUTCDay()]}., ${pad(d.getUTCDate())}.${pad(d.getUTCMonth() + 1)}. 19:00 Uhr</span>` +
    `<a href="/e/${i}"><h2>Konzert ${i}</h2></a></li>`
  ).join("");
  return `<ul>${items}</ul>`;
}

Deno.test("parseScrape: Wochentag verhindert, dass vergangene Termine ohne Jahr ins nächste Jahr rutschen", () => {
  const dayMs = 24 * 60 * 60 * 1000;
  const past = new Date(Date.now() - 60 * dayMs);
  const future = new Date(Date.now() + 60 * dayMs);
  const { events } = parseScrape(listing([past, future]), {
    itemSelector: "li.ev",
    titleSelector: "h2",
    dateSelector: ".d",
    urlSelector: "a[href]",
    baseUrl: "https://example.org",
  });
  assertEquals(events.map((e) => e.startDateTime.slice(0, 10)), [
    past.toISOString().slice(0, 10),
    future.toISOString().slice(0, 10),
  ]);
});

Deno.test("parseScrape: venueAllowlist greift vor und nach venueNameMap, venueAfterSelector + venueStripPattern", () => {
  const html = `<ul>
    <li class="ev"><div class="m">12. Okt, 19:00 <a href="/a"><h2>A</h2></a><div class="t">Konzert</div>Neuer Konzertsaal, Rennweg 8, 1030 Wien</div></li>
    <li class="ev"><div class="m">13. Okt, 19:00 <a href="/b"><h2>B</h2></a><div class="t">Konzert</div>Großer Saal</div></li>
    <li class="ev"><div class="m">14. Okt, 19:00 <a href="/c"><h2>C</h2></a><div class="t">Konzert</div>Woanders</div></li>
  </ul>`;
  const { events } = parseScrape(html, {
    itemSelector: "li.ev",
    titleSelector: "h2",
    dateSelector: ".m",
    urlSelector: "a[href]",
    baseUrl: "https://example.org",
    venueAfterSelector: ".t",
    venueStripPattern: ",\\s*[^,]+,\\s*\\d{4}\\s+Wien.*$",
    venueNameMap: { "Neuer Konzertsaal": "mdw", "Großer Saal": "Konzerthaus Berlin" },
    venueAllowlist: ["mdw", "Großer Saal"],
  });
  assertEquals(events.map((e) => [e.title, e.venueName, e.startDateTime.slice(11, 16)]), [
    ["A", "mdw", "19:00"],
    ["B", "Konzerthaus Berlin", "19:00"],
  ]);
});
