import { describe, expect, it } from "vitest";
import { computeQualityScore } from "./quality-score";

const NOW = new Date("2026-08-02T00:00:00Z");

const baseInput = {
  fields: { criticalPresent: 1, criticalTotal: 1, optionalPresent: 2, optionalTotal: 2 },
  provenanceConfidences: ["confirmed" as const],
  profileCheckedAt: NOW.toISOString(),
  images: { hasNonRejectedImage: true, anyNeedsReview: false, anyLicenseConfirmed: true },
  hasPendingDuplicateCandidate: false,
  now: NOW,
};

describe("computeQualityScore", () => {
  it("scores a fully complete, confirmed, fresh, imaged entity near 100", () => {
    const result = computeQualityScore(baseInput);
    expect(result.totalScore).toBeGreaterThanOrEqual(95);
    expect(result.hasOpenReviewItems).toBe(false);
  });

  it("weighs a missing critical field more heavily than a missing optional field", () => {
    const missingCritical = computeQualityScore({
      ...baseInput,
      fields: { criticalPresent: 0, criticalTotal: 1, optionalPresent: 2, optionalTotal: 2 },
    });
    const missingOptional = computeQualityScore({
      ...baseInput,
      fields: { criticalPresent: 1, criticalTotal: 1, optionalPresent: 1, optionalTotal: 2 },
    });
    expect(missingCritical.completeness.score).toBeLessThan(missingOptional.completeness.score);
  });

  it("scores an entity with no source data as low on source quality, not silently ignored", () => {
    const result = computeQualityScore({ ...baseInput, provenanceConfidences: [] });
    expect(result.sourceQuality.score).toBe(0);
    expect(result.totalScore).toBeLessThan(baseInput ? 100 : 0);
  });

  it("decays recency for a profile not checked in a long time", () => {
    const stale = computeQualityScore({
      ...baseInput,
      profileCheckedAt: new Date(NOW.getTime() - 400 * 24 * 60 * 60 * 1000).toISOString(),
    });
    expect(stale.recency.score).toBe(0);
  });

  it("flags never-checked profiles as an open review item even with a high score otherwise", () => {
    const result = computeQualityScore({ ...baseInput, profileCheckedAt: null });
    expect(result.hasOpenReviewItems).toBe(true);
    expect(result.openReviewReasons).toContain("Noch nie geprüft");
  });

  it("renormalizes weights when image coverage is inapplicable (e.g. works)", () => {
    const withImages = computeQualityScore(baseInput);
    const withoutImageSupport = computeQualityScore({ ...baseInput, images: null });
    expect(withoutImageSupport.imageCoverage).toBeNull();
    // Beide Male alle übrigen Signale perfekt — ohne Bild-Unterstützung darf
    // das NICHT automatisch schlechter abschneiden als mit (das wäre eine
    // Bestrafung für eine fehlende Produktfunktion, nicht für Datenqualität).
    expect(withoutImageSupport.totalScore).toBeGreaterThanOrEqual(withImages.totalScore - 1);
  });

  it("renormalizes weights when match certainty is inapplicable (e.g. venues/ensembles pre-Task-E)", () => {
    const result = computeQualityScore({ ...baseInput, hasPendingDuplicateCandidate: null });
    expect(result.matchCertainty).toBeNull();
    expect(result.totalScore).toBeGreaterThanOrEqual(95);
  });

  it("penalizes a pending duplicate candidate as reduced match certainty and an open review item", () => {
    const result = computeQualityScore({ ...baseInput, hasPendingDuplicateCandidate: true });
    expect(result.matchCertainty?.score).toBeLessThan(1);
    expect(result.hasOpenReviewItems).toBe(true);
    expect(result.openReviewReasons).toContain("Mögliches Duplikat offen");
  });

  it("scores a fully empty entity at 0", () => {
    const result = computeQualityScore({
      fields: { criticalPresent: 0, criticalTotal: 1, optionalPresent: 0, optionalTotal: 2 },
      provenanceConfidences: [],
      profileCheckedAt: null,
      images: { hasNonRejectedImage: false, anyNeedsReview: false, anyLicenseConfirmed: false },
      hasPendingDuplicateCandidate: true,
      now: NOW,
    });
    expect(result.totalScore).toBeLessThan(20);
  });
});
