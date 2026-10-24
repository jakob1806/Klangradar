import { assertEquals } from "jsr:@std/assert@1";
import { findProgramBooklet } from "./programBooklet.ts";

Deno.test("findProgramBooklet: Programmheft-PDF wird erkannt, Saisonbroschüre nicht", () => {
  const html = `<a href="/files/brso-saison-2627.pdf">Saisonbroschüre</a>
    <a href="/media/konzert-12-programmheft.pdf">Programmheft (PDF)</a>`;
  assertEquals(findProgramBooklet(html, "https://example.org/konzert"), "https://example.org/media/konzert-12-programmheft.pdf");
});

Deno.test("findProgramBooklet: issuu-Link", () => {
  const html = `<a href="https://issuu.com/haus/docs/abend">Digitales Programm</a>`;
  assertEquals(findProgramBooklet(html, "https://example.org/"), "https://issuu.com/haus/docs/abend");
});

Deno.test("findProgramBooklet: nichts gefunden", () => {
  assertEquals(findProgramBooklet(`<a href="/tickets">Tickets</a>`, "https://example.org/"), null);
});
