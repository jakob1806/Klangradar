import { assertEquals } from "jsr:@std/assert@1";
import { raceImageSources } from "./raceImageSources.ts";

function found<T>(candidate: T, score: number) {
  return () => Promise.resolve({ candidate, score });
}
function notFound() {
  return () => Promise.resolve(null);
}
function errors(message: string) {
  return () => Promise.reject(new Error(message));
}

Deno.test("raceImageSources: within the same tier, highest score wins", async () => {
  const result = await raceImageSources([
    { source: "duckduckgo", tier: 2, run: found("ddg-image", 4) },
    { source: "gemini", tier: 2, run: found("gemini-image", 7) },
  ]);
  assertEquals(result.winner?.candidate, "gemini-image");
  assertEquals(result.winner?.source, "gemini");
});

Deno.test("raceImageSources: a lower tier number wins over a higher-scored higher tier", async () => {
  const result = await raceImageSources([
    { source: "official-site", tier: 0, run: found("official-image", 3) },
    { source: "duckduckgo", tier: 2, run: found("ddg-image", 9) },
  ]);
  assertEquals(result.winner?.candidate, "official-image");
  assertEquals(result.winner?.source, "official-site");
});

Deno.test("raceImageSources: falls through to a higher tier when the lower tier found nothing", async () => {
  const result = await raceImageSources([
    { source: "official-site", tier: 0, run: notFound() },
    { source: "wikipedia", tier: 1, run: found("wiki-image", 5) },
  ]);
  assertEquals(result.winner?.candidate, "wiki-image");
});

Deno.test("raceImageSources: a failing source does not block the others", async () => {
  const result = await raceImageSources([
    { source: "official-site", tier: 0, run: errors("network error") },
    { source: "wikipedia", tier: 1, run: found("wiki-image", 5) },
  ]);
  assertEquals(result.winner?.candidate, "wiki-image");
  const officialAttempt = result.attempts.find((a) => a.source === "official-site");
  assertEquals(officialAttempt?.outcome, "error");
});

Deno.test("raceImageSources: returns a null winner when every source finds nothing", async () => {
  const result = await raceImageSources([
    { source: "official-site", tier: 0, run: notFound() },
    { source: "wikipedia", tier: 1, run: notFound() },
  ]);
  assertEquals(result.winner, null);
  assertEquals(result.attempts.length, 2);
});

Deno.test("raceImageSources: records every attempt outcome regardless of the winner", async () => {
  const result = await raceImageSources([
    { source: "official-site", tier: 0, run: found("official-image", 1) },
    { source: "wikipedia", tier: 1, run: found("wiki-image", 10) },
    { source: "commons", tier: 1, run: notFound() },
  ]);
  assertEquals(result.attempts.length, 3);
  assertEquals(result.winner?.candidate, "official-image");
});
