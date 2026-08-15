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

Deno.test("Gärtnerplatz keeps a substage as event detail", () => {
  const html = `<div class="vorstellung performance vorstellung-5477 ort-107">
    <div class="col-xl-3"><div class="fs-3">Sa, 19.12.26</div><div class="fw-bold">14.30 Uhr</div>
      <div class="text-produktion-font-color"><span>Probebühne</span></div></div>
    <div class="fs-3"><a href="/workshop?ID_Vorstellung=5477">Workshop</a></div>
  </div><div class="vorstellung performance vorstellung-5180 ort-112">
    <div class="col-xl-3"><div class="fs-3">Sa, 27.02.27</div><div class="fw-bold">19.00 Uhr</div></div>
    <div class="fs-3"><a href="/gastspiel">Gastspiel</a></div></div>`;
  const result = parseScrape(html, {
    itemSelector: ".vorstellung.performance",
    itemAllowClassContains: ["ort-57", "ort-107"],
    titleSelector: ".fs-3 a", urlSelector: ".fs-3 a",
    dateSelector: ".col-xl-3 .fs-3", timeSelector: ".col-xl-3 .fw-bold",
    venueDetailSelector: ".col-xl-3 .text-produktion-font-color span",
  });
  assertEquals(result.events.length, 1);
  assertEquals(result.events[0].venueDetail, "Probebühne");
});
