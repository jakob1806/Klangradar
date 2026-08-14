import {
  basicNameIssues,
  deduplicateIssues,
  findNameCandidates,
  nameSimilarity,
  normalizeName,
} from "./heuristics.ts";

Deno.test("normalizeName treats diacritics, ampersands and whitespace consistently", () => {
  if (
    normalizeName("  Münchner  & Philharmoniker ") !==
      "munchner und philharmoniker"
  ) {
    throw new Error("Name was not normalized as expected");
  }
});

Deno.test("findNameCandidates catches exact variants and surname-only persons", () => {
  const candidates = findNameCandidates("current", "Rattle", [
    { id: "full", name: "Sir Simon Rattle" },
    { id: "other", name: "Kirill Petrenko" },
  ]);
  if (
    candidates.length !== 1 || candidates[0].id !== "full" ||
    candidates[0].score < 0.9
  ) {
    throw new Error(`Unexpected candidates: ${JSON.stringify(candidates)}`);
  }
});

Deno.test("similar spelling receives a high but non-exact score", () => {
  const score = nameSimilarity(
    "Münchner Philharmoniker",
    "Muenchner Philharmoniker",
  );
  if (score < 0.8 || score >= 1) throw new Error(`Unexpected score: ${score}`);
});

Deno.test("person with one name and bad whitespace gets explainable issues", () => {
  const issues = basicNameIssues("person", "  Rattle  ");
  const ids = new Set(issues.map((issue) => issue.id));
  if (!ids.has("name-whitespace") || !ids.has("person-single-name")) {
    throw new Error(`Missing expected issues: ${JSON.stringify(issues)}`);
  }
});

Deno.test("ensemble name with markdown artifacts and generic wording gets flagged", () => {
  const issues = basicNameIssues("ensemble", "**Chor**");
  const ids = new Set(issues.map((issue) => issue.id));
  if (!ids.has("name-markdown-artifact") || !ids.has("ensemble-generic-name")) {
    throw new Error(`Missing expected issues: ${JSON.stringify(issues)}`);
  }
});

Deno.test("real ensemble name with markdown artifacts only flags the markdown issue", () => {
  const issues = basicNameIssues("ensemble", "**Bayerischer Staatsopernchor**");
  const ids = new Set(issues.map((issue) => issue.id));
  if (!ids.has("name-markdown-artifact") || ids.has("ensemble-generic-name")) {
    throw new Error(`Unexpected issues: ${JSON.stringify(issues)}`);
  }
});

Deno.test("deduplicateIssues removes identical report entries", () => {
  const issue = {
    id: "a",
    severity: "warning" as const,
    category: "name" as const,
    message: "Name prüfen",
    source: "rule" as const,
  };
  if (deduplicateIssues([issue, { ...issue, id: "b" }]).length !== 1) {
    throw new Error("Duplicate issues were not removed");
  }
});
