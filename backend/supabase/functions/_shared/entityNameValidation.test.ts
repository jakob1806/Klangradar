import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { assessEnsembleName } from "./entityNameValidation.ts";

Deno.test("accepts explicit ensemble names", () => {
  assertEquals(assessEnsembleName("Symphonieorchester des Bayerischen Rundfunks").safe, true);
  assertEquals(assessEnsembleName("Belcea Quartet").safe, true);
});

Deno.test("rejects ticket copy and prose", () => {
  assertEquals(assessEnsembleName("Ticketverkauf an der Abendkasse").safe, false);
  assertEquals(assessEnsembleName("weitere Informationen erhalten Sie hier").safe, false);
});

Deno.test("holds likely persons for review", () => {
  const result = assessEnsembleName("Johann Sebastian Bach");
  assertEquals(result.safe, false);
  assertEquals(result.reason, "sieht wie ein Personenname aus");
});
