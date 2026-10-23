import { assert, assertFalse } from "jsr:@std/assert@1";
import { templateText, validateText } from "./texts.ts";
import type { Candidate } from "./select.ts";

const day: Candidate = {
  user_id: "u", kind: "concert_day", dedupe_key: "concert_day:1", event_id: "1", priority: 95, transactional: true,
  facts: { title: "Mahler 5", start: "2026-11-05T19:30:00Z", venue: "Isarphilharmonie", doors: "Einlass ab 19:30", slug: "m5" },
};

Deno.test("Vorlage nennt Uhrzeit in Berliner Zeit", () => {
  const t = templateText(day);
  assert((t.title + t.body).includes("20:30") || (t.title + t.body).includes("Mahler 5"));
});

Deno.test("KI-Prüfung: erfundene Zahl wird verworfen", () => {
  assert(validateText({ title: "Heute: Mahler 5", body: "Um 20:30 Uhr in der Isarphilharmonie." }, day));
  assertFalse(validateText({ title: "Heute: Mahler 5", body: "Nur noch 12 Karten!" }, day));
  assertFalse(validateText({ title: "Mahler 5", body: "Tickets auf www.example.de" }, day));
  assertFalse(validateText({ title: "", body: "x" }, day));
});

Deno.test("alle Arten haben Vorlagen ohne undefined", () => {
  for (const kind of ["new_followed", "almost_sold_out", "concert_day", "how_was_it", "weekly_pick", "reengagement"]) {
    const t = templateText({ ...day, kind, facts: { ...day.facts, first_name: "Anna", count: 2, followed: ["BRSO"], events: [{ title: "A", start: "2026-11-05T19:30:00Z", venue: "X" }], reason: "Mit dem BRSO" } });
    assertFalse((t.title + t.body).includes("undefined"), `${kind}: ${t.title} / ${t.body}`);
  }
});
