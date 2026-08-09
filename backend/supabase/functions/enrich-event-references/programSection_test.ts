import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  extractProgramSection,
  findProgramContextForWork,
} from "./programSection.ts";

Deno.test("extractProgramSection trennt BRSO-Programm von Mitwirkenden", () => {
  const section = extractProgramSection(`Galerie öffnen
Programm
Laura Bowler
»The White Book« für Sopran und Orchester
Pause
Claude Debussy
»Danse sacrée et Danse profane« für Harfe und Streicher
Igor Strawinsky
Ballettmusik zu »Petruschka« (1947)
Mitwirkende
Barbara Hannigan`);

  assertEquals(
    section,
    `Laura Bowler
»The White Book« für Sopran und Orchester
Pause
Claude Debussy
»Danse sacrée et Danse profane« für Harfe und Streicher
Igor Strawinsky
Ballettmusik zu »Petruschka« (1947)`,
  );
});

Deno.test("extractProgramSection erkennt MKO-Programm und stoppt vor Empfehlungen", () => {
  const section = extractProgramSection(`Programm
Claude Debussy,
Petite Suite (Orchestrierung Henri Büsser)
Claude Vivier,
Lonely Child für Sopran und Kammerorchester
Pause
Chaya Czernowin,
Birds für Streichorchester
Joseph Haydn,
Sinfonia Nr.102
Ähnliche Konzerte
15.10.2026`);

  assertEquals(section?.includes("Joseph Haydn"), true);
  assertEquals(section?.includes("15.10.2026"), false);
});

Deno.test("extractProgramSection lehnt generischen Einzeiler ab", () => {
  assertEquals(
    extractProgramSection("Programm\nWerke von Mozart\nTickets"),
    null,
  );
  assertEquals(
    extractProgramSection("Beschreibung\nEin festlicher Konzertabend"),
    null,
  );
});

Deno.test("findProgramContextForWork ordnet Komponist und Pause deterministisch zu", () => {
  const section = `Laura Bowler
»The White Book« für Sopran und Orchester
Pause
Claude Debussy
»Danse sacrée et Danse profane« für Harfe und Streicher
Igor Strawinsky
Ballettmusik zu »Petruschka« (1947)`;
  assertEquals(
    findProgramContextForWork(
      section,
      "»The White Book« für Sopran und Orchester",
    ),
    {
      composerName: "Laura Bowler",
      afterIntermission: false,
    },
  );
  assertEquals(
    findProgramContextForWork(section, "Ballettmusik zu »Petruschka« (1947)"),
    {
      composerName: "Igor Strawinsky",
      afterIntermission: true,
    },
  );
});
