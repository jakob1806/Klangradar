import { describe, expect, it } from "vitest";
import { isAllowedFeedUrl, previewFeed } from "./feed-preview";

describe("previewFeed", () => {
  it("liest iCal mit gefalteten Zeilen und TZID", () => {
    const ics = [
      "BEGIN:VCALENDAR",
      "BEGIN:VEVENT",
      "SUMMARY:Brahms\\, Sinfonie Nr. 4 –",
      "  Abo A",
      "DTSTART;TZID=Europe/Berlin:20261024T193000",
      "END:VEVENT",
      "BEGIN:VEVENT",
      "SUMMARY:Orgelmatinee",
      "DTSTART;VALUE=DATE:20261101",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");
    expect(previewFeed(ics)).toEqual({
      type: "ical",
      count: 2,
      samples: [
        { title: "Brahms, Sinfonie Nr. 4 – Abo A", start: "2026-10-24 19:30" },
        { title: "Orgelmatinee", start: "2026-11-01" },
      ],
    });
  });

  it("liest RSS-Items", () => {
    const rss = `<?xml version="1.0"?><rss><channel><item><title><![CDATA[Liederabend & Gäste]]></title><pubDate>Sat, 24 Oct 2026 19:30:00 +0200</pubDate></item></channel></rss>`;
    const preview = previewFeed(rss);
    expect(preview?.type).toBe("rss");
    expect(preview?.samples[0].title).toBe("Liederabend & Gäste");
  });

  it("findet schema.org-Events in @graph", () => {
    const html = `<html><script type="application/ld+json">{"@graph":[{"@type":"MusicEvent","name":"Mahler 2","startDate":"2026-11-12T20:00:00+01:00"},{"@type":"Organization"}]}</script></html>`;
    expect(previewFeed(html)).toEqual({ type: "schema_org", count: 1, samples: [{ title: "Mahler 2", start: "2026-11-12 20:00" }] });
  });

  it("gibt null für Seiten ohne Termine", () => {
    expect(previewFeed("<html><body>Hallo</body></html>")).toBeNull();
  });
});

describe("isAllowedFeedUrl", () => {
  it("wandelt webcal in https", () => {
    expect(isAllowedFeedUrl("webcal://example.org/cal.ics")?.toString()).toBe("https://example.org/cal.ics");
  });
  it("lehnt interne Adressen ab", () => {
    for (const url of ["http://localhost/x", "http://127.0.0.1/x", "http://192.168.1.2/x", "http://172.20.0.1/x", "ftp://example.org/x", "kein link"]) {
      expect(isAllowedFeedUrl(url)).toBeNull();
    }
  });
});
