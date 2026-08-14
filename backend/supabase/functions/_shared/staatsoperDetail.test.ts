import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseStaatsoperDetail } from "./staatsoperDetail.ts";

Deno.test("parses Staatsoper production image and performing cast", () => {
  const markdown = `
![Image 1: BMW GLOBAL Partner](https://www.staatsoper.de/fileadmin/user_upload/bmw_logo_gray.png)
![Image 2](https://www.staatsoper.de/media/_processed_/e/4/csm_Cenerentola.jpg)
## Besetzung
*   **Musikalische Leitung**[Antonino Fogliani](https://www.staatsoper.de/biographien/fogliani-antonino)
*   **Inszenierung**[Jean-Pierre Ponnelle](https://www.staatsoper.de/biographien/ponnelle-jean-pierre)
*   **Chor**[Franz Obermair](https://www.staatsoper.de/biographien/obermair-franz)
*   **Don Ramiro**[Liam Bonthrone](https://www.staatsoper.de/biographien/bonthorne-liam)
*   **Violine**[So-Young Kim](https://www.staatsoper.de/biographien/kim-so-young)[Julia Pfister](https://www.staatsoper.de/biographien/pfister-julia-1)
*   Bayerisches Staatsorchester
*   Bayerischer Staatsopernchor
## Kommende Vorstellungen`;
  const detail = parseStaatsoperDetail(markdown);
  assertEquals(detail.hasCastSection, true);
  assertEquals(detail.imageUrl, "https://www.staatsoper.de/media/_processed_/e/4/csm_Cenerentola.jpg");
  assertEquals(detail.participants.map((p) => [p.name, p.role, p.type]), [
    ["Antonino Fogliani", "dirigent", "person"],
    ["Franz Obermair", "chorleiter", "person"],
    ["Liam Bonthrone", "solist", "person"],
    ["So-Young Kim", "solist", "person"],
    ["Julia Pfister", "solist", "person"],
    ["Bayerisches Staatsorchester", null, "ensemble"],
    ["Bayerischer Staatsopernchor", null, "ensemble"],
  ]);
});

Deno.test("parses complete Staatsoper concert program", () => {
  const detail = parseStaatsoperDetail(`
*   Programm Mehr laden
**Saverio Tasca**
_San Giusto_ für Vibraphon und Streicher
**Andy Akiho**
_Aluminous_ für Vibraphon und Streicher
_LigNEous_ V für Marimba und Streicher
## Besetzung`);
  assertEquals(detail.works, [
    { title: "San Giusto für Vibraphon und Streicher", composerName: "Saverio Tasca", position: 0 },
    { title: "Aluminous für Vibraphon und Streicher", composerName: "Andy Akiho", position: 1 },
    { title: "LigNEous V für Marimba und Streicher", composerName: "Andy Akiho", position: 2 },
  ]);
});
