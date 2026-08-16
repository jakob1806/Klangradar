import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { extractHeroImageFromMarkdown, extractMarkdownImageCredit, markdownToSyntheticHtml } from "./readerProxyImage.ts";
import { discoverSubpageLinks } from "./officialSiteImageSearch.ts";

Deno.test("extractHeroImageFromMarkdown skips site logo and picks first plausible content image", () => {
  const markdown = `
![Logo](https://example.org/assets/logo.svg)
![Menu icon](https://example.org/assets/icon-menu.png)

# Konzertabend im Herkulessaal

![Image 2](https://example.org/media/konzertabend-hero.jpg)

Weiterer Text ...`;
  assertEquals(
    extractHeroImageFromMarkdown(markdown, "https://example.org/events/konzertabend"),
    "https://example.org/media/konzertabend-hero.jpg",
  );
});

Deno.test("extractHeroImageFromMarkdown resolves relative image URLs against the page URL", () => {
  const markdown = `![Image 1](/media/hero.jpg)`;
  assertEquals(
    extractHeroImageFromMarkdown(markdown, "https://example.org/events/konzertabend"),
    "https://example.org/media/hero.jpg",
  );
});

Deno.test("extractHeroImageFromMarkdown returns null when only generic images are present", () => {
  const markdown = `
![Logo](https://example.org/logo.png)
![Placeholder](https://example.org/default-og-image.jpg)`;
  assertEquals(extractHeroImageFromMarkdown(markdown, "https://example.org"), null);
});

Deno.test("extractMarkdownImageCredit finds a copyright line", () => {
  const markdown = `Titelbild\n\n© Max Mustermann 2026\n\nWeiterer Text`;
  assertEquals(extractMarkdownImageCredit(markdown), "© Max Mustermann 2026");
});

Deno.test("extractMarkdownImageCredit returns null without a credit line", () => {
  assertEquals(extractMarkdownImageCredit("Kein Hinweis auf Bildrechte hier."), null);
});

Deno.test("markdownToSyntheticHtml emits img/a tags that discoverSubpageLinks can still find", () => {
  const markdown = `
[Presse](https://example.org/presse)
![Ensemble-Foto](https://example.org/media/ensemble.jpg)
[Startseite](https://example.org/)`;
  const html = markdownToSyntheticHtml(markdown, "https://example.org/ueber-uns");
  assertEquals(html.includes('<img src="https://example.org/media/ensemble.jpg" alt="Ensemble-Foto">'), true);
  assertEquals(
    discoverSubpageLinks(html, "https://example.org/ueber-uns", "example.org"),
    ["https://example.org/presse"],
  );
});
