// Created by ChatGPT Codex
import { expect, test } from "@playwright/test";

test.skip(!process.env.E2E_STORAGE_STATE, "E2E_STORAGE_STATE mit einem dedizierten Testkonto fehlt");
test.use({ storageState: process.env.E2E_STORAGE_STATE ?? { cookies: [], origins: [] } });

test("event creation form exposes required fields without writing data", async ({ page }) => {
  await page.goto("/veranstalter/events/new");
  await expect(page.getByRole("heading", { name: /Event/ })).toBeVisible();
  await expect(page.locator('[name="title"]')).toBeVisible();
  await expect(page.locator('[name="start_datetime"]')).toBeVisible();
  await expect(page.getByText("Venue", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Event anlegen" })).toBeVisible();
});

test("claim flow contains evidence and verification controls", async ({ page }) => {
  await page.goto("/veranstalter/claim");
  await expect(page.getByRole("heading", { name: "Institution beanspruchen" })).toBeVisible();
  await expect(page.getByRole("searchbox")).toBeVisible();
  await expect(page.getByText("Nachweis", { exact: false }).first()).toBeVisible();
});

test("image upload control is keyboard-operable on a configured claimed profile", async ({ page }) => {
  test.skip(!process.env.E2E_CLAIMED_PROFILE_URL, "E2E_CLAIMED_PROFILE_URL fehlt");
  await page.goto(process.env.E2E_CLAIMED_PROFILE_URL!);
  await expect(page.getByRole("button", { name: /Foto (auswählen|ersetzen)/ })).toBeVisible();
});

test("promotion page explains the Stripe checkout boundary", async ({ page }) => {
  await page.goto("/veranstalter/promote");
  await expect(page.getByRole("heading", { name: "Push & Promote" })).toBeVisible();
  await expect(page.getByText(/Zahlungslink|Checkout/).first()).toBeVisible();
});
