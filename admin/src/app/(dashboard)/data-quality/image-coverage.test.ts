import { describe, expect, it } from "vitest";
import { aggregateImageCoverage, type ImageRow } from "./image-coverage";

const COUNTS = { venues: 2, persons: 2, ensembles: 1, events: 3 };

describe("aggregateImageCoverage", () => {
  it("counts an origin as covered only by a non-rejected image", () => {
    const images: ImageRow[] = [
      { origin_type: "venue", origin_id: "v1", license_status: "confirmed_free", needs_review: false, content_hash: "a" },
      { origin_type: "venue", origin_id: "v2", license_status: "rejected", needs_review: false, content_hash: "b" },
    ];
    const report = aggregateImageCoverage(images, COUNTS, 0);
    expect(report.venues.withImage).toBe(1);
  });

  it("counts needs_review across all images regardless of license status", () => {
    const images: ImageRow[] = [
      { origin_type: "person", origin_id: "p1", license_status: "unknown", needs_review: true, content_hash: null },
      { origin_type: "person", origin_id: "p2", license_status: "confirmed_free", needs_review: false, content_hash: null },
    ];
    const report = aggregateImageCoverage(images, COUNTS, 0);
    expect(report.needsReviewCount).toBe(1);
  });

  it("flags a content_hash shared by two different origins as one duplicate group", () => {
    const images: ImageRow[] = [
      { origin_type: "venue", origin_id: "v1", license_status: "unknown", needs_review: false, content_hash: "same" },
      { origin_type: "person", origin_id: "p1", license_status: "unknown", needs_review: false, content_hash: "same" },
    ];
    const report = aggregateImageCoverage(images, COUNTS, 0);
    expect(report.duplicateContentHashGroups).toBe(1);
  });

  it("does not flag multiple images for the SAME origin as a duplicate group", () => {
    // Ein Origin darf mehrere Bilder mit demselben content_hash haben (z.B.
    // Original + reimportierter Duplikat-Versuch für dasselbe Event) — das
    // ist keine Dublette im Sinn dieses Berichts, nur echte Wiederverwendung
    // über verschiedene Origins hinweg zählt.
    const images: ImageRow[] = [
      { origin_type: "venue", origin_id: "v1", license_status: "unknown", needs_review: false, content_hash: "same" },
      { origin_type: "venue", origin_id: "v1", license_status: "unknown", needs_review: false, content_hash: "same" },
    ];
    const report = aggregateImageCoverage(images, COUNTS, 0);
    expect(report.duplicateContentHashGroups).toBe(0);
  });

  it("tallies license status distribution", () => {
    const images: ImageRow[] = [
      { origin_type: "venue", origin_id: "v1", license_status: "confirmed_free", needs_review: false, content_hash: null },
      { origin_type: "venue", origin_id: "v2", license_status: "confirmed_free", needs_review: false, content_hash: null },
      { origin_type: "person", origin_id: "p1", license_status: "unknown", needs_review: false, content_hash: null },
    ];
    const report = aggregateImageCoverage(images, COUNTS, 0);
    expect(report.licenseStatusCounts).toEqual({ confirmed_free: 2, unknown: 1 });
  });

  it("passes through totals and event image coverage unchanged", () => {
    const report = aggregateImageCoverage([], COUNTS, 2);
    expect(report.venues.total).toBe(2);
    expect(report.events.total).toBe(3);
    expect(report.events.withImage).toBe(2);
    expect(report.totalImages).toBe(0);
  });
});
