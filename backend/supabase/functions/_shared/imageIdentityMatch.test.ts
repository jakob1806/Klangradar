// Testet nur die reine, deterministische classifyMatch()-Logik —
// assessImageIdentityMatch() selbst braucht einen echten AI-Provider-Call
// (callAiFunction/_shared/ai/router.ts) und ist damit kein sinnvoller
// Kandidat für einen isolierten Unit-Test ohne eine Dependency-Injection-
// Seam in router.ts (siehe Plan: bewusst als eigener, separat zu
// genehmigender Schritt zurückgestellt — betrifft gemeinsame
// Infrastruktur, die auch resolve-person-duplicates nutzt).
import { assertEquals } from "jsr:@std/assert@1";
import { AUTO_APPROVE_THRESHOLD, classifyMatch, REJECT_THRESHOLD } from "./imageIdentityMatch.ts";

Deno.test("classifyMatch: high score, no conflicts -> approved", () => {
  assertEquals(classifyMatch(0.95, []), "approved");
});

Deno.test("classifyMatch: exactly at the auto-approve threshold -> approved", () => {
  assertEquals(classifyMatch(AUTO_APPROVE_THRESHOLD, []), "approved");
});

Deno.test("classifyMatch: just below the auto-approve threshold -> pending_review", () => {
  assertEquals(classifyMatch(AUTO_APPROVE_THRESHOLD - 0.01, []), "pending_review");
});

Deno.test("classifyMatch: low score, no conflicts -> rejected", () => {
  assertEquals(classifyMatch(0.1, []), "rejected");
});

Deno.test("classifyMatch: exactly at the reject threshold -> pending_review (not rejected)", () => {
  assertEquals(classifyMatch(REJECT_THRESHOLD, []), "pending_review");
});

Deno.test("classifyMatch: just below the reject threshold -> rejected", () => {
  assertEquals(classifyMatch(REJECT_THRESHOLD - 0.01, []), "rejected");
});

Deno.test("classifyMatch: mid-range score, no conflicts -> pending_review", () => {
  assertEquals(classifyMatch(0.6, []), "pending_review");
});

Deno.test("classifyMatch: high score BUT a conflict is flagged -> pending_review, never approved", () => {
  assertEquals(classifyMatch(0.99, ["Bildunterschrift nennt ein anderes Sterbejahr"]), "pending_review");
});

Deno.test("classifyMatch: low score with a conflict -> still pending_review, not rejected", () => {
  // Ein Konflikt ist ein "das muss ein Mensch entscheiden"-Signal, kein
  // zusätzliches Argument für Ablehnung — ein Mensch könnte den Konflikt
  // als harmlos einstufen (z.B. Tippfehler in der Quelle).
  assertEquals(classifyMatch(0.1, ["Name leicht abweichend geschrieben"]), "pending_review");
});

Deno.test("classifyMatch: multiple conflicts -> pending_review", () => {
  assertEquals(classifyMatch(0.95, ["Konflikt A", "Konflikt B"]), "pending_review");
});
