import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { brsoSubscriptions, mphilSubscriptions, musikvereinSubscriptions, seasonFor, wienerSymphonikerSubscriptions } from "./subscriptions.ts";

Deno.test("season", () => {
  assertEquals(seasonFor("2026-10-01T18:00:00Z"), "2026/27");
  assertEquals(seasonFor("2027-06-03T18:00:00Z"), "2026/27");
});

Deno.test("mphil topline", () => {
  const html = `<p class="m-mphil-concert-detail__topline"> Subscription B </p><p class="m-mphil-concert-detail__topline">Abonnement Kammerkonzert</p>`;
  assertEquals(mphilSubscriptions(html).map((s) => s.code), ["B", "Kammerkonzert"]);
});

Deno.test("brso per date", () => {
  const html = `Donnerstag 1 Juli 2027 20.00 Uhr Herkulessaal <span> ABO D </span> Freitag 2 Juli 2027 20.00 Uhr <span>ABO C</span> Samstag 3 Juli 2027`;
  assertEquals(brsoSubscriptions(html, "2027-07-02T18:00:00Z").map((s) => s.code), ["C"]);
  assertEquals(brsoSubscriptions(html, "2027-07-03T18:00:00Z"), []);
});

Deno.test("musikverein cycles", () => {
  const subs = musikvereinSubscriptions({ distributionChannels: { data: [
    { code: "MEIIII2627", description_D: "Meisterinterpret:innen III" }, { code: "WEB", description_D: "Online" },
  ] } });
  assertEquals(subs.map((s) => s.name), ["Meisterinterpret:innen III"]);
});

Deno.test("wiener symphoniker", () => {
  const html = `<p class="s-accent-text-l">Konzert ist Teil des Abonnements &bdquo;Die Große Symphonie B&rdquo;</p> <div><a href="/abonnement/die-grosse-symphonie-b-2026-27" class="s-link">`;
  const s = wienerSymphonikerSubscriptions(html);
  assertEquals(s[0].name, "Die Große Symphonie B");
  assertEquals(s[0].url, "https://www.wienersymphoniker.at/abonnement/die-grosse-symphonie-b-2026-27");
});
