// Created by ChatGPT Codex
import { expect, test } from "@playwright/test";

test("öffentliche interne Links liefern keine Fehlerseite", async ({ page, request, baseURL }) => {
  const queue = ["/", "/impressum", "/datenschutz"];
  const checked = new Set<string>();

  while (queue.length > 0) {
    const path = queue.shift();
    if (!path || checked.has(path)) continue;
    checked.add(path);

    const response = await request.get(path);
    expect(response.ok(), `${path} antwortet mit HTTP ${response.status()}`).toBe(true);

    await page.goto(path);
    for (const href of await page.locator('a[href]').evaluateAll((links) =>
      links.map((link) => (link as HTMLAnchorElement).href)
    )) {
      const url = new URL(href);
      if (url.origin === new URL(baseURL!).origin && !checked.has(url.pathname)) {
        queue.push(url.pathname);
      }
    }
  }
});
