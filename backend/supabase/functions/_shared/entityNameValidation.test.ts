import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { assessEnsembleName, cleanEntityName } from "./entityNameValidation.ts";

Deno.test("accepts explicit ensemble names", () => {
  assertEquals(assessEnsembleName("Symphonieorchester des Bayerischen Rundfunks").safe, true);
  assertEquals(assessEnsembleName("Belcea Quartet").safe, true);
  assertEquals(assessEnsembleName("hr-Bigband").safe, true);
  assertEquals(assessEnsembleName("via-nova-chor München").safe, true);
  assertEquals(assessEnsembleName("Orchester der Bayerischen Staatsoper").safe, true);
});

Deno.test("decodes HTML and rejects promotional sentence fragments", () => {
  assertEquals(
    cleanEntityName("Erleben Sie zuerst das Konzert&nbsp; und entscheiden anschließend."),
    "Erleben Sie zuerst das Konzert und entscheiden anschließend.",
  );
  assertEquals(assessEnsembleName("Erleben Sie zuerst das Konzert und entscheiden anschließend,&nbsp;").classification, "text");
  assertEquals(assessEnsembleName("was Sie dafür zahlen können oder möchten.").classification, "text");
});

Deno.test("rejects generic names before accepting ensemble markers", () => {
  for (const name of ["Chor", "**Chor**", "Orchester", "Ensemble", "Blechbläser", "Opernstudio", "Quatuor"]) {
    const result = assessEnsembleName(name);
    assertEquals(result.safe, false, name);
    assertEquals(result.classification, "generic", name);
  }
});

Deno.test("classifies common wrong entity types", () => {
  assertEquals(assessEnsembleName("Chiara Braggion, Réka Kristóf").classification, "multiple_people");
  assertEquals(assessEnsembleName("Elmar Hauser").classification, "person");
  assertEquals(assessEnsembleName("Bayerischer Rundfunk").classification, "organization");
  assertEquals(assessEnsembleName("Theater Liberi").classification, "organization");
  assertEquals(assessEnsembleName("St. Michael Kirche").classification, "venue");
  assertEquals(assessEnsembleName("Statisterie des Staatstheaters am Gärtnerplatz").classification, "role_or_department");
  assertEquals(assessEnsembleName("**Ballettmeister Drosselmeier** N.N.").classification, "role_or_department");
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
