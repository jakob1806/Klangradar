import type { MetadataRoute } from "next";

const origin = process.env.NEXT_PUBLIC_APP_URL ?? "https://klangradar.com";

export default function sitemap(): MetadataRoute.Sitemap {
  return ["/", "/impressum", "/datenschutz", "/nutzungsbedingungen"].map((path) => ({ url: `${origin}${path}`, lastModified: new Date(), changeFrequency: "monthly", priority: path === "/" ? 1 : 0.3 }));
}
