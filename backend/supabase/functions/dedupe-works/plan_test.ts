import { assertEquals } from "jsr:@std/assert@1";
import { planMerges } from "./plan.ts";

Deno.test("führt Varianten desselben Komponisten zusammen, behält das meistgenutzte", () => {
  const merges = planMerges([
    { id: "a", title: "4. Sinfonie", composer_id: "brahms", catalog_number: null, uses: 1 },
    { id: "b", title: "Sinfonie Nr. 4 e-Moll op. 98", composer_id: "brahms", catalog_number: "op. 98", uses: 5 },
    { id: "c", title: "Symphony No. 4", composer_id: "brahms", catalog_number: null, uses: 0 },
    { id: "d", title: "Sinfonie Nr. 4", composer_id: "beethoven", catalog_number: null, uses: 2 },
    { id: "e", title: "Sinfonie Nr. 3", composer_id: "brahms", catalog_number: null, uses: 1 },
    { id: "f", title: "Sinfonie Nr. 4", composer_id: null, catalog_number: null, uses: 1 },
  ]);
  assertEquals(merges.map((m) => `${m.drop}->${m.keep}`).sort(), ["a->b", "c->b"]);
});
