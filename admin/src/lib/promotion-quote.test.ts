import { describe, expect, it } from "vitest";
import { euroToCents, promotionWindow } from "./promotion-quote";

// Erstellt von Claude Code (29.10.2026).
describe("euroToCents", () => {
  it("liest deutsche Beträge", () => {
    expect(euroToCents("12,50")).toBe(1250);
    expect(euroToCents("150")).toBe(15000);
    expect(euroToCents("")).toBeNull();
    expect(euroToCents("abc")).toBe("invalid");
    expect(euroToCents("-3")).toBe("invalid");
  });
});

describe("promotionWindow", () => {
  const now = "2026-11-01T10:00:00.000Z";
  it("startet frühestens jetzt und endet spätestens mit dem Konzert", () => {
    const window = promotionWindow("2026-10-30", "2026-11-20", "2026-11-10T18:00:00.000Z", now);
    expect(window.startsAt).toBe(now);
    expect(window.endsAt).toBe("2026-11-10T18:00:00.000Z");
  });
  it("endet um Mitternacht nach dem letzten Tag (Münchner Zeit)", () => {
    const window = promotionWindow("2026-11-05", "2026-11-07", "2026-11-10T18:00:00.000Z", now);
    expect(window.startsAt).toBe("2026-11-04T23:00:00.000Z");
    expect(window.endsAt).toBe("2026-11-07T23:00:00.000Z");
  });
});
