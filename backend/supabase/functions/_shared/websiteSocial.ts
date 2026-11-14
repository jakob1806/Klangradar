// Erstellt von Claude Code (14.11.2026): offizielle Social-Media-Links von
// der eigenen Website lesen (Kopf/Fußzeile). Ergänzt die Wikidata-Recherche,
// die nur bekannte Künstler:innen abdeckt. Teilen-/Intent-Links und die
// Konten von Ticketanbietern/CMS werden ignoriert.

const PATTERNS: [string, RegExp][] = [
  ["instagram", /https?:\/\/(?:www\.)?instagram\.com\/([A-Za-z0-9_.]{2,30})\/?(?=["'?#<\s])/gi],
  ["facebook", /https?:\/\/(?:www\.|de-de\.|m\.)?facebook\.com\/((?!sharer|share|dialog|plugins|tr\b|events\/)[A-Za-z0-9_.\-]{3,80})\/?(?=["'?#<\s])/gi],
  ["youtube", /https?:\/\/(?:www\.)?youtube\.com\/((?:@|channel\/|c\/|user\/)[A-Za-z0-9_.\-]{2,80})\/?(?=["'?#<\s])/gi],
  ["x", /https?:\/\/(?:www\.)?(?:twitter|x)\.com\/((?!intent|share|home|search)[A-Za-z0-9_]{2,30})\/?(?=["'?#<\s])/gi],
  ["tiktok", /https?:\/\/(?:www\.)?tiktok\.com\/(@[A-Za-z0-9_.]{2,30})\/?(?=["'?#<\s])/gi],
  ["linkedin", /https?:\/\/(?:[a-z]{2,3}\.)?linkedin\.com\/((?:company|in)\/[A-Za-z0-9_\-%]{2,100})\/?(?=["'?#<\s])/gi],
  ["threads", /https?:\/\/(?:www\.)?threads\.(?:net|com)\/(@[A-Za-z0-9_.]{2,30})\/?(?=["'?#<\s])/gi],
  ["bluesky", /https?:\/\/bsky\.app\/profile\/([A-Za-z0-9_.\-]{3,80})\/?(?=["'?#<\s])/gi],
  ["soundcloud", /https?:\/\/(?:www\.)?soundcloud\.com\/((?!discover|search)[A-Za-z0-9_\-]{2,60})\/?(?=["'?#<\s])/gi],
];

const BASE: Record<string, string> = {
  instagram: "https://www.instagram.com/", facebook: "https://www.facebook.com/", youtube: "https://www.youtube.com/",
  x: "https://x.com/", tiktok: "https://www.tiktok.com/", linkedin: "https://www.linkedin.com/",
  threads: "https://www.threads.net/", bluesky: "https://bsky.app/profile/", soundcloud: "https://soundcloud.com/",
};

// Konten von Plattformen/Dienstleistern, die oft im Footer fremder Seiten stehen.
const IGNORE = /^(eventim|reservix|ticketmaster|wix|wordpress|squarespace|jimdo|instagram|facebook|youtube|twitter|meta|google|shopify|p|explore|watch|tr|login)$/i;

/** Liest die Startseite und liefert je Plattform den häufigsten Link. */
export async function socialLinksFromWebsite(website: string): Promise<Record<string, string>> {
  let html = "";
  try {
    const res = await fetch(website, {
      redirect: "follow",
      signal: AbortSignal.timeout(12000),
      headers: { "User-Agent": "Mozilla/5.0 (compatible; KlangradarBot/1.0; +https://klangradar.com)" },
    });
    if (!res.ok || !(res.headers.get("content-type") ?? "").includes("html")) return {};
    html = (await res.text()).slice(0, 1_500_000);
  } catch {
    return {};
  }
  const out: Record<string, string> = {};
  for (const [platform, pattern] of PATTERNS) {
    const counts = new Map<string, number>();
    for (const match of html.matchAll(pattern)) {
      const handle = match[1].replace(/\/+$/, "");
      const first = handle.replace(/^@/, "").split("/").pop() ?? "";
      if (IGNORE.test(first)) continue;
      counts.set(handle, (counts.get(handle) ?? 0) + 1);
    }
    const best = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
    if (best) out[platform] = BASE[platform] + best[0];
  }
  return out;
}
