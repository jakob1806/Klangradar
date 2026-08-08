// Tests für die SSRF-Schutzfunktion (isPublicImageUrl) und die generische-
// Bild-Erkennung (isLikelyGenericImage) — beides reine, netzwerkfreie
// Funktionen, bisher ungetestet trotz sicherheitskritischer Rolle (jede
// externe URL, die die Bilder-Pipeline oder der neue offizielle-Website-
// Crawler abruft, läuft zuerst durch isPublicImageUrl). Testfall-Liste
// Abschnitt 13, Punkt 13: "eine URL versucht, auf eine private IP-Adresse
// zuzugreifen".
import { assertEquals } from "jsr:@std/assert@1";
import { isLikelyGenericImage, isPublicImageUrl } from "./imageValidation.ts";

Deno.test("isPublicImageUrl: allows ordinary public https/http URLs", () => {
  assertEquals(isPublicImageUrl("https://example.com/photo.jpg"), true);
  assertEquals(isPublicImageUrl("http://example.com/photo.jpg"), true);
});

Deno.test("isPublicImageUrl: blocks localhost in all its forms", () => {
  assertEquals(isPublicImageUrl("http://localhost/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://sub.localhost/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://127.0.0.1/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://[::1]/photo.jpg"), false);
});

Deno.test("isPublicImageUrl: blocks private IPv4 ranges", () => {
  assertEquals(isPublicImageUrl("http://10.0.0.5/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://172.16.0.5/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://172.31.255.255/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://192.168.1.1/photo.jpg"), false);
  // 172.15.x/172.32.x liegen AUSSERHALB des privaten 172.16-31-Bereichs
  assertEquals(isPublicImageUrl("http://172.15.0.5/photo.jpg"), true);
  assertEquals(isPublicImageUrl("http://172.32.0.5/photo.jpg"), true);
});

Deno.test("isPublicImageUrl: blocks the cloud metadata endpoint (link-local range)", () => {
  assertEquals(isPublicImageUrl("http://169.254.169.254/latest/meta-data/"), false);
});

Deno.test("isPublicImageUrl: blocks .local hostnames and IPv6 unique-local ranges", () => {
  assertEquals(isPublicImageUrl("http://printer.local/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://[fd00::1]/photo.jpg"), false);
  assertEquals(isPublicImageUrl("http://[fe80::1]/photo.jpg"), false);
});

Deno.test("isPublicImageUrl: blocks non-http(s) protocols including file://", () => {
  assertEquals(isPublicImageUrl("file:///etc/passwd"), false);
  assertEquals(isPublicImageUrl("ftp://example.com/photo.jpg"), false);
  assertEquals(isPublicImageUrl("data:image/png;base64,iVBORw0KGgo="), false);
});

Deno.test("isPublicImageUrl: rejects unparseable strings instead of throwing", () => {
  assertEquals(isPublicImageUrl("not a url"), false);
  assertEquals(isPublicImageUrl(""), false);
});

Deno.test("isLikelyGenericImage: flags logos, placeholders, banners and default og:images", () => {
  assertEquals(isLikelyGenericImage("https://example.com/img/logo.png"), true);
  assertEquals(isLikelyGenericImage("https://example.com/img/site-logo-2024.png"), true);
  assertEquals(isLikelyGenericImage("https://example.com/img/placeholder.jpg"), true);
  assertEquals(isLikelyGenericImage("https://example.com/img/hero-banner.jpg"), true);
  assertEquals(isLikelyGenericImage("https://example.com/default--og-image--mm.jpg"), true);
});

Deno.test("isLikelyGenericImage: leaves a plausible press photo filename alone", () => {
  assertEquals(isLikelyGenericImage("https://example.com/presse/julia-fischer-portrait.jpg"), false);
});
