import { assertEquals } from "jsr:@std/assert@1";
import { selectPushes, type Candidate, type UserContext } from "./select.ts";

const c = (kind: string, priority: number, transactional = false, user = "u"): Candidate =>
  ({ user_id: user, kind, dedupe_key: `${kind}:1`, event_id: null, priority, transactional, facts: {} });
const ctx = (o: Partial<UserContext> = {}): Map<string, UserContext> =>
  new Map([["u", { sentLastDay: 0, sentLastWeek: 0, preferredHour: 18, engagement: {}, ...o }]]);
// 18:10 Uhr Berlin (Winterzeit: UTC+1)
const evening = new Date("2026-11-05T17:10:00Z");
const morning = new Date("2026-11-05T09:10:00Z"); // 10:10 Berlin
const night = new Date("2026-11-05T22:30:00Z"); // 23:30 Berlin

Deno.test("wichtigste Mitteilung zur bevorzugten Stunde", () => {
  assertEquals(selectPushes([c("weekly_pick", 50), c("almost_sold_out", 80)], ctx(), evening).map((x) => x.kind), ["almost_sold_out"]);
});

Deno.test("Ruhezeit", () => {
  assertEquals(selectPushes([c("almost_sold_out", 80)], ctx(), night), []);
});

Deno.test("Budget gilt nicht für Konzerttag", () => {
  const busy = ctx({ sentLastDay: 1, sentLastWeek: 3 });
  assertEquals(selectPushes([c("weekly_pick", 50)], busy, evening), []);
  assertEquals(selectPushes([c("concert_day", 95, true)], busy, morning).map((x) => x.kind), ["concert_day"]);
});

Deno.test("Konzerttag nur vormittags", () => {
  assertEquals(selectPushes([c("concert_day", 95, true)], ctx(), evening), []);
});

Deno.test("selten geöffnete Arten entfallen", () => {
  const bored = ctx({ engagement: { weekly_pick: { sent: 10, opened: 0 } } });
  assertEquals(selectPushes([c("weekly_pick", 50)], bored, evening), []);
  assertEquals(selectPushes([c("almost_sold_out", 80)], ctx({ engagement: { almost_sold_out: { sent: 10, opened: 0 } } }), evening).length, 1);
});
