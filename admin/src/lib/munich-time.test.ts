import { describe, expect, it } from "vitest";
import { munichLocalToISOString, toMunichDatetimeLocal } from "./munich-time";

describe("Europe/Berlin date conversion", () => {
  it("uses CEST in summer", () => {
    expect(munichLocalToISOString("2027-06-28T19:00")).toBe("2027-06-28T17:00:00.000Z");
  });

  it("uses CET in winter", () => {
    expect(munichLocalToISOString("2027-01-15T19:00")).toBe("2027-01-15T18:00:00.000Z");
  });

  it("round-trips an ISO timestamp independently of the server timezone", () => {
    expect(toMunichDatetimeLocal("2027-06-28T17:00:00.000Z")).toBe("2027-06-28T19:00");
  });

  it("rejects a nonexistent DST-gap time", () => {
    expect(() => munichLocalToISOString("2027-03-28T02:30")).toThrow(/Zeitumstellung/);
  });
});
