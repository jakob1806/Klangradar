import { assertEquals } from "jsr:@std/assert@1";
import { dailyLimit, selectPushes, type Candidate, type UserContext } from "./select.ts";

const c = (kind: string, priority: number, transactional = false, user = "u", key = `${kind}:1`): Candidate =>
  ({ user_id: user, kind, dedupe_key: key, event_id: null, priority, transactional, facts: {} });
const ctx = (o: Partial<UserContext> = {}): Map<string, UserContext> =>
  new Map([["u", { sentLastDay: 0, sentLastWeek: 0, preferredHour: 18, engagement: {}, ...o }]]);
// 18:10 Uhr Berlin (Winterzeit: UTC+1)
const evening = new Date("2026-11-05T17:10:00Z");
const morning = new Date("2026-11-05T09:10:00Z"); // 10:10 Berlin
const noon = new Date("2026-11-05T11:10:00Z"); // 12:10 Berlin
const night = new Date("2026-11-05T22:30:00Z"); // 23:30 Berlin

Deno.test("wichtigste Mitteilung zur bevorzugten Stunde", () => {
  assertEquals(selectPushes([c("weekly_pick", 50), c("almost_sold_out", 80)], ctx(), evening).map((x) => x.kind), ["almost_sold_out"]);
});

Deno.test("Ruhezeit", () => {
  assertEquals(selectPushes([c("almost_sold_out", 80)], ctx(), night), []);
});

Deno.test("Wochenbudget: Standard 10, selbst wählbar", () => {
  assertEquals(selectPushes([c("weekly_pick", 50)], ctx({ sentLastWeek: 9 }), evening).length, 1);
  assertEquals(selectPushes([c("weekly_pick", 50)], ctx({ sentLastWeek: 10 }), evening), []);
  assertEquals(selectPushes([c("weekly_pick", 50)], ctx({ sentLastWeek: 10, weeklyLimit: 20 }), evening).length, 1);
});

Deno.test("Tagesgrenze und Abstand", () => {
  assertEquals(dailyLimit(10), 3);
  assertEquals(dailyLimit(5), 2);
  assertEquals(selectPushes([c("weekly_pick", 50)], ctx({ sentLastDay: 3 }), evening), []);
  const recent = evening.getTime() - 3600 * 1000;
  assertEquals(selectPushes([c("weekly_pick", 50)], ctx({ sentLastDay: 1, lastSentAt: recent }), evening), []);
});

Deno.test("Planung (Konzerttag) kommt trotz ausgeschöpftem Budget, aber nur vormittags", () => {
  const busy = ctx({ sentLastDay: 5, sentLastWeek: 40 });
  assertEquals(selectPushes([c("concert_day", 95, true)], busy, morning).map((x) => x.kind), ["concert_day"]);
  assertEquals(selectPushes([c("concert_day", 95, true)], ctx(), evening), []);
});

Deno.test("kein Plus-Sofort mehr: Neuankündigungen nur im Budget", () => {
  const busy = ctx({ sentLastWeek: 10 });
  assertEquals(selectPushes([c("new_followed", 70)], busy, evening), []);
});

Deno.test("zweite Plus-Sammlung mittags", () => {
  const midday = c("new_followed", 70, false, "u", "new_followed:2026-11-05a");
  assertEquals(selectPushes([midday], ctx(), noon).length, 1);
  assertEquals(selectPushes([midday], ctx(), evening), []);
});

Deno.test("selten geöffnete Arten entfallen", () => {
  const bored = ctx({ engagement: { weekly_pick: { sent: 10, opened: 0 } } });
  assertEquals(selectPushes([c("weekly_pick", 50)], bored, evening), []);
  assertEquals(selectPushes([c("almost_sold_out", 80)], ctx({ engagement: { almost_sold_out: { sent: 10, opened: 0 } } }), evening).length, 1);
});
