import { assertEquals } from "jsr:@std/assert@1";
import { upgradeImageUrl } from "./imageUrlUpgrade.ts";

Deno.test("upgradeImageUrl: in-muenchen Vorschaubild → volle Größe", () => {
  assertEquals(
    upgradeImageUrl("https://www.in-muenchen.de/cdn-cgi/imagedelivery/SDG/e6dd/w=265,h=186,fit=cover"),
    "https://www.in-muenchen.de/cdn-cgi/imagedelivery/SDG/e6dd/w=1600,fit=scale-down",
  );
  assertEquals(upgradeImageUrl("https://example.org/a.jpg"), "https://example.org/a.jpg");
});
