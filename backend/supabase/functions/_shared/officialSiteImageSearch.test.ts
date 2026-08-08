// Tests für die reinen, netzwerkfreien Bausteine der offizielle-Website-
// Bildersuche (Phase-8-Erweiterung, Testfall-Liste Abschnitt 13). Der
// eigentliche Crawl (searchOfficialSiteForImages) braucht echten
// Netzwerkzugriff/einen Mock-Server und ist hier bewusst NICHT getestet —
// siehe Schlussbericht für diese Einschränkung. Scoring, Dekorativ-Filter
// und Unterseiten-Erkennung sind dagegen reine Funktionen und vollständig
// isoliert testbar.
import { assertEquals } from "jsr:@std/assert@1";
import { discoverSubpageLinks, isDecorative, scoreCandidate, type RawCandidate } from "./officialSiteImageSearch.ts";

const CONTEXT = { entityName: "Julia Fischer", siteHost: "juliafischer.com" };

function candidate(overrides: Partial<Parameters<typeof scoreCandidate>[0]> = {}) {
  return {
    url: "https://juliafischer.com/presse/foto.jpg",
    source: "content" as const,
    isPressPage: false,
    altText: null,
    widthHint: null,
    heightHint: null,
    positionIndex: 99,
    ...overrides,
  };
}

Deno.test("scoreCandidate: schema.org image on the press page with a name match reaches high confidence", () => {
  const { confidence, score } = scoreCandidate(
    candidate({
      source: "json_ld",
      isPressPage: true,
      altText: "Julia Fischer beim Konzert",
      widthHint: 1200,
    }),
    CONTEXT,
  );
  assertEquals(confidence, "high");
  if (score < 6) throw new Error(`expected score >= 6, got ${score}`);
});

Deno.test("scoreCandidate: a bare content image with no other signal stays low confidence", () => {
  // Bewusst eine fremde Domain OHNE Namensbestandteil — "juliafischer.com"
  // (die Standard-candidate()-URL) würde sonst selbst den Namensabgleich
  // auslösen (die Domain enthält "julia"+"fischer" als Teilstring) und so
  // versehentlich einen zweiten, hier nicht gemeinten Score-Faktor testen.
  const { confidence } = scoreCandidate(
    candidate({ url: "https://cdn.example.net/assets/img-123.jpg" }),
    CONTEXT,
  );
  assertEquals(confidence, "low");
});

Deno.test("scoreCandidate: og:image alone lands in the medium range", () => {
  const { confidence } = scoreCandidate(candidate({ source: "og_image" }), CONTEXT);
  assertEquals(confidence, "medium");
});

Deno.test("scoreCandidate: a logo field is penalized even with other positive signals", () => {
  const withoutLogo = scoreCandidate(candidate({ source: "json_ld", isPressPage: true }), CONTEXT);
  const withLogo = scoreCandidate(candidate({ source: "json_ld", isPressPage: true, isLogoField: true }), CONTEXT);
  if (withLogo.score >= withoutLogo.score) {
    throw new Error("logo candidate should score strictly lower than the equivalent non-logo candidate");
  }
});

Deno.test("scoreCandidate: low width hint is penalized, high width hint is rewarded", () => {
  const small = scoreCandidate(candidate({ widthHint: 200 }), CONTEXT);
  const large = scoreCandidate(candidate({ widthHint: 1200 }), CONTEXT);
  if (small.score >= large.score) {
    throw new Error("a small width hint should score lower than a large one, all else equal");
  }
});

Deno.test("scoreCandidate: an image on the official domain scores higher than one on a foreign domain", () => {
  const own = scoreCandidate(candidate({ url: "https://juliafischer.com/img/foto.jpg" }), CONTEXT);
  const foreign = scoreCandidate(candidate({ url: "https://cdn.example.net/img/foto.jpg" }), CONTEXT);
  if (own.score <= foreign.score) {
    throw new Error("same-domain image should outscore a foreign-domain image, all else equal");
  }
});

Deno.test("isDecorative: rejects icons, sprites, tracking pixels and SVGs", () => {
  const base: RawCandidate = {
    url: "https://example.com/img/photo.jpg",
    pageUrl: "https://example.com/",
    source: "content",
    isPressPage: false,
    altText: null,
    widthHint: null,
    heightHint: null,
    positionIndex: 0,
  };
  assertEquals(isDecorative({ ...base, url: "https://example.com/icons/social-icon-facebook.png" }), true);
  assertEquals(isDecorative({ ...base, url: "https://example.com/img/tracking-pixel.gif" }), true);
  assertEquals(isDecorative({ ...base, url: "https://example.com/img/logo.svg" }), true);
  assertEquals(isDecorative({ ...base, altText: "Cookie-Banner schließen" }), true);
});

Deno.test("isDecorative: rejects tiny dimension hints (icon-sized) and extreme aspect ratios (banners)", () => {
  const base: RawCandidate = {
    url: "https://example.com/img/photo.jpg",
    pageUrl: "https://example.com/",
    source: "content",
    isPressPage: false,
    altText: null,
    widthHint: null,
    heightHint: null,
    positionIndex: 0,
  };
  assertEquals(isDecorative({ ...base, widthHint: 32, heightHint: 32 }), true);
  assertEquals(isDecorative({ ...base, widthHint: 1800, heightHint: 60 }), true); // 30:1 banner
  assertEquals(isDecorative({ ...base, widthHint: 1200, heightHint: 900 }), false); // normales Foto
});

Deno.test("isDecorative: accepts a plausible press photo unchanged", () => {
  const photo: RawCandidate = {
    url: "https://example.com/presse/portrait.jpg",
    pageUrl: "https://example.com/presse",
    source: "hero",
    isPressPage: true,
    altText: "Porträtfoto",
    widthHint: 1600,
    heightHint: 1200,
    positionIndex: 0,
  };
  assertEquals(isDecorative(photo), false);
});

const SUBPAGE_HTML = `
  <nav>
    <a href="/presse">Presse</a>
    <a href="/ueber-uns">Über uns</a>
    <a href="/shop">Shop</a>
    <a href="https://other-host.example/kontakt">Kontakt (fremder Host)</a>
    <a href="/presse">Presse (Duplikat)</a>
    <a href="/team.html">Unser Team</a>
  </nav>
`;

Deno.test("discoverSubpageLinks: matches press/about/team keywords, ignores unrelated links", () => {
  const links = discoverSubpageLinks(SUBPAGE_HTML, "https://example.com/", "example.com");
  assertEquals(links.includes("https://example.com/presse"), true);
  assertEquals(links.includes("https://example.com/ueber-uns"), true);
  assertEquals(links.includes("https://example.com/team.html"), true);
  assertEquals(links.some((l) => l.includes("/shop")), false);
});

Deno.test("discoverSubpageLinks: excludes links to a different host (no cross-site crawling)", () => {
  const links = discoverSubpageLinks(SUBPAGE_HTML, "https://example.com/", "example.com");
  assertEquals(links.some((l) => l.includes("other-host.example")), false);
});

Deno.test("discoverSubpageLinks: deduplicates repeated links to the same subpage", () => {
  const links = discoverSubpageLinks(SUBPAGE_HTML, "https://example.com/", "example.com");
  const presseCount = links.filter((l) => l === "https://example.com/presse").length;
  assertEquals(presseCount, 1);
});
