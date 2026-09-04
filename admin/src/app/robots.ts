import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: "*", allow: ["/", "/impressum", "/datenschutz", "/nutzungsbedingungen"], disallow: ["/login", "/events", "/veranstalter", "/api", "/auth"] }],
    sitemap: "https://klangradar.com/sitemap.xml",
  };
}
