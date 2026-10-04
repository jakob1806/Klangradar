import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { jsonApiNextUrl, parseJsonApi } from "./json_api.ts";

const config = {
  itemsPath: "results",
  idPath: "id",
  titlePath: "title",
  startPath: "start_date",
  endPath: "end_date",
  venuePath: "room",
  descriptionPath: "subtitle",
  ticketPath: "ticket_link",
  imagePath: "image.url",
  urlTemplate: "/de/programm/{slug}",
  baseUrl: "https://www.alteoper.de",
  nextPath: "next",
  skipPastPath: "is_past",
};

const body = JSON.stringify({
  count: 3,
  next: "https://www.alteoper.de/de/api/events/?page=2",
  results: [
    {
      id: 18930, slug: "behind-the-scenes", room: "Albert Mangelsdorff Foyer",
      start_date: "2026-10-04T18:00:00+02:00", end_date: "2026-10-04T18:45:00+02:00",
      title: "Behind the scenes", subtitle: "Pre-concert talk",
      ticket_link: "https://www.alteoper.de/de/forms/behind-the-scenes/",
      image: { url: "/media/a.jpg" }, is_past: false,
    },
    { id: 1, slug: "alt", title: "Vorbei", start_date: "2020-01-01T10:00:00+01:00", is_past: true },
    { id: 2, slug: "kaputt", title: "Ohne Datum", start_date: "nope" },
  ],
});

Deno.test("parseJsonApi: mappt Felder per Pfad und löst relative URLs auf", () => {
  const { events, errors } = parseJsonApi(body, config);
  assertEquals(events.length, 1);
  const e = events[0];
  assertEquals(e.externalId, "18930");
  assertEquals(e.url, "https://www.alteoper.de/de/programm/behind-the-scenes");
  assertEquals(e.ticketUrl, "https://www.alteoper.de/de/forms/behind-the-scenes/");
  assertEquals(e.imageUrl, "https://www.alteoper.de/media/a.jpg");
  assertEquals(e.venueDetail, "Albert Mangelsdorff Foyer");
  assertEquals(errors.length, 1); // "Ohne Datum"; vergangene Items werden still übersprungen
});

Deno.test("jsonApiNextUrl: liefert Folgeseite oder null", () => {
  assertEquals(jsonApiNextUrl(body, config), "https://www.alteoper.de/de/api/events/?page=2");
  assertEquals(jsonApiNextUrl(JSON.stringify({ next: null }), config), null);
});

Deno.test("parseJsonApi: falscher itemsPath ergibt Fehler statt stillem Nichts", () => {
  const r = parseJsonApi(body, { ...config, itemsPath: "data" });
  assertEquals(r.events.length, 0);
  assertEquals(r.errors.length, 1);
});
