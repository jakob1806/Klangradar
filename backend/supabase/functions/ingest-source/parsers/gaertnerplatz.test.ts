import { assertEquals } from "jsr:@std/assert@1";
import { parseScrape } from "./scrape.ts";

Deno.test("Gärtnerplatz config parses two-digit year and dotted time", () => {
  const html = `<div class="vorstellung performance vorstellung-5395 ort-57">
    <div class="col-xl-3"><div class="fs-3">So, 20.09.26</div><div class="fw-bold">18.00–20.30 Uhr</div></div>
    <div class="fs-3"><a href="./produktionen/la-traviata.html?ID_Vorstellung=5395">La traviata</a></div>
    <div class="children-without-margin">Oper in drei Akten</div>
  </div>`;
  const result = parseScrape(html, {
    itemSelector: '.vorstellung.performance[class*="vorstellung-"]',
    itemExcludeClassContains: ["ort-102"],
    titleSelector: ".fs-3 a",
    urlSelector: ".fs-3 a",
    dateSelector: ".col-xl-3 .fs-3",
    timeSelector: ".col-xl-3 .fw-bold",
    descriptionSelector: ".children-without-margin",
    baseUrl: "https://www.gaertnerplatztheater.de/de/",
  });
  assertEquals(result.errors, []);
  assertEquals(result.events[0].startDateTime, "2026-09-20T18:00:00+02:00");
  assertEquals(result.events[0].title, "La traviata");
});

Deno.test("Gärtnerplatz config excludes guest venues", () => {
  const html = `<div class="vorstellung performance vorstellung-1 ort-102"><div class="col-xl-3"><div class="fs-3">So, 20.09.26</div><div class="fw-bold">18.00 Uhr</div></div><div class="fs-3"><a href="/x">Gastspiel</a></div></div>`;
  const result = parseScrape(html, {
    itemSelector: '.vorstellung.performance[class*="vorstellung-"]',
    itemExcludeClassContains: ["ort-102"],
    titleSelector: ".fs-3 a",
    urlSelector: ".fs-3 a",
    dateSelector: ".col-xl-3 .fs-3",
    timeSelector: ".col-xl-3 .fw-bold",
  });
  assertEquals(result.events.length, 0);
});
