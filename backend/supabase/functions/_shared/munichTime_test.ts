import { munichDayRange } from "./munichTime.ts";

Deno.test("Münchner Tagesgrenzen verwenden im Sommer CEST", () => {
  const range = munichDayRange(1, new Date("2027-06-27T12:00:00Z"));
  if (range.start.toISOString() !== "2027-06-27T22:00:00.000Z") {
    throw new Error("Unerwarteter Start: " + range.start.toISOString());
  }
  if (range.end.toISOString() !== "2027-06-28T21:59:59.999Z") {
    throw new Error("Unerwartetes Ende: " + range.end.toISOString());
  }
});

Deno.test("Münchner Tagesgrenzen verwenden im Winter CET", () => {
  const range = munichDayRange(1, new Date("2027-01-14T12:00:00Z"));
  if (range.start.toISOString() !== "2027-01-14T23:00:00.000Z") {
    throw new Error("Unerwarteter Start: " + range.start.toISOString());
  }
  if (range.end.toISOString() !== "2027-01-15T22:59:59.999Z") {
    throw new Error("Unerwartetes Ende: " + range.end.toISOString());
  }
});
