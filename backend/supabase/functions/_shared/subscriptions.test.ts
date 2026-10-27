// Erstellt von Claude Code (27.10.2026): Abo-Erkennung der Münchner Quellen.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  berlinLocal, brChorSubscriptions, brsoCalendarIndex, brsoKey, brsoSubscriptions, gaertnerplatzSeries, gaertnerplatzSubscriptions,
  mkoSubscriptions, mphilSubscriptions, musikvereinSubscriptions, rundfunkorchesterSubscriptions,
} from "./subscriptions.ts";

Deno.test("brso: Inline-Skript mit '<' verschluckt den Seitentext nicht mehr", () => {
  const html = `<script>if (a < b) { x(); }</script><div>Sonntag 28 Februar 2027 18.00 Uhr</div>` +
    `<p>10 €</p><span>ABO S</span><h2>Programm</h2><div>Weitere Konzerte Donnerstag 4 März 2027</div>`;
  assertEquals(brsoSubscriptions(html, "2027-02-28T17:00:00Z").map((s) => s.code), ["S"]);
});

Deno.test("brso: Datum mehrfach auf der Seite – alle Abschnitte zählen", () => {
  const html = `<meta>Sonntag 28 Februar 2027</meta><div>Freitag 26 Februar 2027 ABO A</div>` +
    `<div>Sonntag 28 Februar 2027 18.00 Uhr ABO S Programm</div>`;
  assertEquals(brsoSubscriptions(html, "2027-02-28T17:00:00Z").map((s) => s.code), ["S"]);
});

Deno.test("rundfunkorchester: Reihe nach dem Preisblock", () => {
  const html = `<p>€ 69,– | 10,– (U30)</p><p>Sonntagskonzerte</p><p>„Hochdramatisch …“</p>`;
  assertEquals(rundfunkorchesterSubscriptions(html).map((s) => s.name), ["Sonntagskonzerte"]);
});

Deno.test("br-chor: Chor-Abonnement", () => {
  assertEquals(brChorSubscriptions("<p>Dieses Konzert ist Teil des Chor-Abonnements.</p>").length, 1);
  assertEquals(brChorSubscriptions("<p>Sonderkonzert</p>").length, 0);
});

Deno.test("mko: Abo-Nummer in URL", () => {
  assertEquals(mkoSubscriptions("https://www.m-k-o.eu/event-detail/3065/26---27%20Abo%203+Erlangen/").length, 1);
  assertEquals(mkoSubscriptions("https://www.m-k-o.eu/event-detail/1/Sonderkonzert/").length, 0);
});

Deno.test("gärtnerplatz: Serien mit Terminen, Zuordnung über Ortszeit", () => {
  const html = `Online-Buchung Premieren-Abo Abo Serie 01 Text Fr, 16.10.26 19.30–22.20 Uhr Die Reise nach Reims ` +
    `Saalplan ansehen Aboplatz auswählen und direkt buchen Abo Serie 11 So, 20.09.26 18.00–20.30 Uhr La traviata ` +
    `direkt buchen Kammerkonzerte Abo Serie 75 So, 18.10.26 11.00 Uhr Kammerkonzert`;
  const series = gaertnerplatzSeries(html);
  assertEquals(series.map((s) => s.name), ["Premieren-Abo (Serie 01)", "Abo-Serie 11", "Kammerkonzerte (Serie 75)"]);
  assertEquals(gaertnerplatzSubscriptions(series, "2026-10-16T17:30:00Z").map((s) => s.code), ["Serie 01"]);
  assertEquals(gaertnerplatzSubscriptions(series, "2026-10-16T18:30:00Z").length, 0);
  assertEquals(berlinLocal("2027-01-08T18:30:00Z"), "2027-01-08 19:30");
});

Deno.test("brso: Kalender ordnet je Datum zu, Gastkonzerte nicht", () => {
  const index = brsoCalendarIndex({ data: { concerts: [
    { url: "https://www.brso.de/konzerte/sir-simon-rattle-julia-hagen/", start: "2026-11-05T20:00:00+01:00", abo: "ABO A" },
    { url: "https://www.brso.de/konzerte/sir-simon-rattle-julia-hagen/", start: "2026-11-07T19:00:00+01:00", abo: "Gastkonzert" },
    { url: "https://www.brso.de/konzerte/kammerkonzert-12/", start: "2027-01-09T20:00:00+01:00", abo: "Kammerkonzert" },
  ] } });
  assertEquals(index.get(brsoKey("https://www.brso.de/konzerte/sir-simon-rattle-julia-hagen/", "2026-11-05T19:00:00Z"))?.map((s) => s.code), ["A"]);
  assertEquals(index.get(brsoKey("https://www.brso.de/konzerte/sir-simon-rattle-julia-hagen", "2026-11-07T18:00:00Z")), undefined);
  assertEquals(index.get(brsoKey("https://www.brso.de/konzerte/kammerkonzert-12/", "2027-01-09T19:00:00Z"))?.[0].name, "Abo Kammerkonzerte");
});

Deno.test("brso: URL-Kodierung egal", () => {
  assertEquals(brsoKey("https://www.brso.de/konzerte/franck-ollu-reudenbach-%c2%b7-iannotta/", "2026-10-30T19:00:00Z"),
    brsoKey("https://www.brso.de/konzerte/franck-ollu-reudenbach-%C2%B7-iannotta/", "2026-10-30T19:00:00Z"));
});

Deno.test("mphil: mehrere Abos in einer Zeile", () => {
  const html = `<p class="concert-detail__topline">\n Subscription F,\n Subscription I4 </p>`;
  assertEquals(mphilSubscriptions(html).map((s) => s.name), ["Abo F", "Abo I4"]);
});

Deno.test("musikverein: Zyklus ohne Namen wird übersprungen", () => {
  const data = { distributionChannels: { data: [{ code: "AEG-K-2627", description_D: "-" }, { code: "KLZ2627", description_D: "Klavier-Zyklus" }] } };
  assertEquals(musikvereinSubscriptions(data).map((s) => s.name), ["Klavier-Zyklus"]);
});
