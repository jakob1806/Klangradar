import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { musikvereinId, parseMusikvereinDetail, stripHtml } from "./musikvereinDetail.ts";

Deno.test("musikvereinId", () => {
  assertEquals(musikvereinId("https://musikverein.at/konzert/?id=0005d01e"), "0005d01e");
  assertEquals(musikvereinId("https://example.com"), null);
});

Deno.test("parse program with intermission and cast", () => {
  const d = parseMusikvereinDetail({
    booking: { data: [{ comm_descr_long_1_HTML_ch_1_D: "<p>Ein <b>großer</b> Abend mit Brahms und Schumann im Goldenen Saal.</p>" }] },
    cast: { data: [
      { name_D: "Tonkünstler-Orchester Niederösterreich", profession_D: "Orchester", role_D: "" },
      { name_D: "Fabien Gabel", profession_D: "Dirigent", role_D: "" },
    ] },
    program: { data: [
      { composer_author: "Robert Schumann", opus_titel_D: "Cellokonzert", order: 2, is_text: 0, is_encore: 0 },
      { composer_author: "Johannes Brahms", opus_titel_D: "Festouvertüre", order: 1, is_text: 0, is_encore: 0 },
      { composer_author: "***", opus_titel_D: "***", order: 3 },
      { composer_author: "Maurice Ravel", opus_titel_D: "La Valse", order: 4, is_text: 0, is_encore: 0 },
      { composer_author: "X", opus_titel_D: "Zugabe", order: 5, is_text: 0, is_encore: 1 },
    ] },
  });
  assertEquals(d.works.map((w) => [w.title, w.position, w.afterIntermission]), [
    ["Festouvertüre", 1, false], ["Cellokonzert", 2, false], ["La Valse", 3, true],
  ]);
  assertEquals(d.participants.map((p) => p.type), ["ensemble", "person"]);
  assertEquals(d.participants[1].role, "Dirigent");
  assertEquals(d.description, "Ein großer Abend mit Brahms und Schumann im Goldenen Saal.");
});

Deno.test("stripHtml removes nested tags", () => {
  assertEquals(stripHtml("<<b>script>x"), "x");
});
