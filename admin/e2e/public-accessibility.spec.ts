// Created by ChatGPT Codex
import { expect, test } from "@playwright/test";

test("public navigation, skip link and legal links work", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveTitle(/Klangradar/);

  await page.keyboard.press("Tab");
  const skipLink = page.getByRole("link", { name: "Zum Inhalt springen" });
  await expect(skipLink).toBeFocused();
  await skipLink.press("Enter");
  await expect(page.locator("#main-content")).toBeFocused();

  await page.getByRole("link", { name: "Datenschutz" }).click();
  await expect(page.getByRole("heading", { name: "Datenschutzerklärung" })).toBeVisible();
  await expect(page).toHaveURL(/\/datenschutz$/);
});

test("login validates email and exposes status messages accessibly", async ({ page }) => {
  await page.goto("/login");
  const email = page.getByLabel("E-Mail-Adresse");
  await email.fill("keine-email");
  await page.getByRole("button", { name: "Code senden" }).click();
  expect(await email.evaluate((node: HTMLInputElement) => node.validity.valid)).toBe(false);
});

test("protected flows redirect to login without leaking dashboard content", async ({ page }) => {
  for (const path of ["/events", "/veranstalter/claim", "/veranstalter/events/new", "/veranstalter/promote"]) {
    await page.goto(path);
    await expect(page).toHaveURL(/\/login\?redirectTo=/);
    await expect(page.getByLabel("E-Mail-Adresse")).toBeVisible();
  }
});
