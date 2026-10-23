import { assertEquals } from "jsr:@std/assert@1";
import { parseMphilProgram } from "./mphilDetail.ts";

// Ausschnitt mphil.de, verifiziert 23.10.2026 (mendelssohn-bartholdy-schumann-2026-10-23).
const HTML = `<ul class="m-mphil-concert-detail__work-list">
<li class="m-mphil-concert-detail__work-item"><a class="m-mphil-concert-detail__work-composer --wrap" href="/x"> Felix Mendelssohn Bartholdy </a>
<p class="m-mphil-concert-detail__work-paragraph"><a class="m-mphil-concert-detail__work-title --wrap" href="/w"><span class="m-mphil-concert-detail__work-title-text">42. Psalm &raquo;Wie der Hirsch&laquo; op. 42</span></a></p></li>
<li class="m-mphil-concert-detail__work-item"><p class="m-mphil-concert-detail__work-paragraph m-mphil-concert-detail__work-title -pause"> Pause </p></li>
<li class="m-mphil-concert-detail__work-item"><a class="m-mphil-concert-detail__work-composer --wrap" href="/y"> Robert Schumann </a>
<p class="m-mphil-concert-detail__work-paragraph"><a class="m-mphil-concert-detail__work-title --wrap" href="/z"><span class="m-mphil-concert-detail__work-title-text">Szenen aus Goethes Faust WoO 3</span></a></p></li>
</ul>`;

Deno.test("liest Programm mit Pause und Komponisten", () => {
  const works = parseMphilProgram(HTML);
  assertEquals(works.map((w) => [w.composerName, w.position, w.afterIntermission]), [
    ["Felix Mendelssohn Bartholdy", 0, false],
    ["Robert Schumann", 1, true],
  ]);
  assertEquals(works[0].title, "42. Psalm »Wie der Hirsch« op. 42");
  assertEquals(works[1].title, "Szenen aus Goethes Faust WoO 3");
});

Deno.test("ohne Werkliste kein Programm", () => {
  assertEquals(parseMphilProgram("<div>kein Programm</div>"), []);
});
