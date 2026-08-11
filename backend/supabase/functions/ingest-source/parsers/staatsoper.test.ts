import { assertEquals } from "jsr:@std/assert@1";
import { parseStaatsoper } from "./staatsoper.ts";

Deno.test("parseStaatsoper reads official schedule links", () => {
  const markdown = `[19. September 2026.9.26 _Samstag_ _Sa._ 18.00 Uhr | Nationaltheater LA CENERENTOLA Gioachino Rossini Weitere Informationen zu LA CENERENTOLA anzeigen - 19.09.2026, 18.00 Uhr Oper](https://www.staatsoper.de/stuecke/la-cenerentola/2026-09-19-1800-16092)`;
  const result = parseStaatsoper(markdown);
  assertEquals(result.errors, []);
  assertEquals(result.events.length, 1);
  assertEquals(result.events[0].title, "LA CENERENTOLA");
  assertEquals(result.events[0].venueName, "Nationaltheater München");
  assertEquals(result.events[0].startDateTime, "2026-09-19T18:00:00+02:00");
  assertEquals(result.events[0].url, "https://www.staatsoper.de/stuecke/la-cenerentola/2026-09-19-1800-16092");
});

Deno.test("parseStaatsoper excludes tours and workshops but keeps ballet", () => {
  const markdown = [
    `[Workshop - Don Giovanni Weitere Informationen zu Workshop - Don Giovanni anzeigen - 01.10.2026, 10.00 Uhr Workshop](https://www.staatsoper.de/stuecke/workshop/2026-10-01-1000-1)`,
    `[01. Oktober 2026 19.30 Uhr | Nationaltheater C A R P A T H I A Weitere Informationen zu C A R P A T H I A anzeigen - 01.10.2026, 19.30 Uhr Ballett](https://www.staatsoper.de/stuecke/carpathia/2026-10-01-1930-2)`,
    `[02. Oktober 2026 19.30 Uhr | Baden-Baden ILLUSIONEN (Gastspiel in Baden-Baden) Weitere Informationen zu ILLUSIONEN (Gastspiel in Baden-Baden) anzeigen - 02.10.2026, 19.30 Uhr Ballett](https://www.staatsoper.de/stuecke/illusionen/2026-10-02-1930-3)`,
    `[03. Oktober 2026 18.00 Uhr | Nationaltheater Öffentliche Bühnenprobe zu Giselle Weitere Informationen zu Öffentliche Bühnenprobe zu Giselle anzeigen - 03.10.2026, 18.00 Uhr Ballett](https://www.staatsoper.de/stuecke/probe/2026-10-03-1800-4)`,
    `[04. Oktober 2026 18.00 Uhr | Nationaltheater Ballett-Kurzführungen Weitere Informationen zu Ballett-Kurzführungen anzeigen - 04.10.2026, 18.00 Uhr Ballett](https://www.staatsoper.de/stuecke/fuehrung/2026-10-04-1800-5)`,
  ].join("\n");
  const result = parseStaatsoper(markdown);
  assertEquals(result.events.map((event) => event.title), ["C A R P A T H I A"]);
});
