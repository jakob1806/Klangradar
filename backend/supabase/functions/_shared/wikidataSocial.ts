// Erstellt von Claude Code (26.10.2026): Offizielle Social-Media-Konten aus
// Wikidata. Nur Treffer mit exakt gleichem Namen UND passendem Typ
// (Musiker:in / Ensemble / Spielstätte) – lieber nichts als ein falsches Konto.
// Wikimedia verlangt einen aussagekräftigen User-Agent mit Kontakt-URL.
const USER_AGENT = "KlangradarBot/1.0 (https://klangradar.com; Social-Links-Abgleich)";

export type SocialEntityType = "person" | "ensemble" | "venue";

const PROPS: Record<string, (v: string) => string> = {
  P2003: (v) => `https://www.instagram.com/${v}/`,
  P2013: (v) => `https://www.facebook.com/${v}`,
  P2002: (v) => `https://x.com/${v}`,
  P2397: (v) => `https://www.youtube.com/channel/${v}`,
  P7085: (v) => `https://www.tiktok.com/@${v}`,
  P6634: (v) => `https://www.linkedin.com/in/${v}/`,
  P4264: (v) => `https://www.linkedin.com/company/${v}/`,
  P11892: (v) => `https://www.threads.net/@${v}`,
  P12361: (v) => `https://bsky.app/profile/${v}`,
  P3040: (v) => `https://soundcloud.com/${v}`,
  P1902: (v) => `https://open.spotify.com/artist/${v}`,
  P2850: (v) => `https://music.apple.com/artist/${v}`,
};
const KEY: Record<string, string> = {
  P2003: "instagram", P2013: "facebook", P2002: "x", P2397: "youtube", P7085: "tiktok",
  P6634: "linkedin", P4264: "linkedin", P11892: "threads", P12361: "bluesky", P3040: "soundcloud",
  P1902: "spotify", P2850: "apple_music",
};

// Berufe (P106) für Personen
const MUSIC_OCCUPATIONS = new Set([
  "Q158852", "Q486748", "Q1259917", "Q177220", "Q2865819", "Q36834", "Q639669", "Q13219637", "Q765778",
  "Q1198887", "Q16145150", "Q12800682", "Q1415090", "Q6168364", "Q2643890", "Q855091", "Q3089940",
  "Q1075651", "Q12902372", "Q18559041", "Q1371925", "Q20198542", "Q4351403", "Q14915627", "Q11063",
]);
// Typen (P31) für Ensembles und Spielstätten
const ENSEMBLE_TYPES = new Set([
  "Q42998", "Q1764494", "Q131186", "Q207338", "Q2088357", "Q1477406", "Q215380", "Q5398426", "Q11405",
  "Q3046146", "Q1542343", "Q4438121", "Q7726467", "Q2281788", "Q1059400",
]);
const VENUE_TYPES = new Set([
  "Q1060829", "Q153562", "Q24354", "Q57660343", "Q2977", "Q16970", "Q856584", "Q15206070", "Q1137809",
  "Q41253", "Q483453", "Q2187088", "Q3152824", "Q13226383", "Q1497364", "Q207694",
]);

export class RateLimited extends Error {}

const norm = (s: string) => s.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

async function api(params: Record<string, string>): Promise<any> {
  const url = `https://www.wikidata.org/w/api.php?${new URLSearchParams({ ...params, format: "json" })}`;
  const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (res.status === 429) throw new RateLimited();
  if (!res.ok) throw new Error(`Wikidata HTTP ${res.status}`);
  return res.json();
}

function values(claims: any, prop: string): string[] {
  return (claims?.[prop] ?? []).filter((c: any) => c.rank !== "deprecated")
    .map((c: any) => c.mainsnak?.datavalue?.value).map((v: any) => typeof v === "string" ? v : v?.id).filter(Boolean);
}

export function matchesType(type: SocialEntityType, claims: any): boolean {
  if (type === "person") return values(claims, "P31").includes("Q5") && values(claims, "P106").some((q) => MUSIC_OCCUPATIONS.has(q));
  const types = values(claims, "P31");
  return types.some((q) => (type === "ensemble" ? ENSEMBLE_TYPES : VENUE_TYPES).has(q));
}

export function socialFromClaims(claims: any): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [prop, build] of Object.entries(PROPS)) {
    const first = values(claims, prop)[0];
    if (first && !out[KEY[prop]]) out[KEY[prop]] = build(first);
  }
  return out;
}

/** Wikidata-ID + Social-Links für einen Namen, oder null bei keinem sicheren Treffer. */
export async function findSocialLinks(type: SocialEntityType, name: string): Promise<{ qid: string; links: Record<string, string>; website?: string } | null> {
  const search = await api({ action: "wbsearchentities", search: name, language: "de", uselang: "de", limit: "5", type: "item" });
  const target = norm(name);
  const candidates = (search.search ?? []).filter((s: any) =>
    norm(s.label ?? "") === target || (s.aliases ?? []).some((a: string) => norm(a) === target) || norm(s.match?.text ?? "") === target);
  if (candidates.length === 0) return null;
  const ids = candidates.map((c: any) => c.id).join("|");
  const data = await api({ action: "wbgetentities", ids, props: "claims" });
  const matching = Object.entries(data.entities ?? {}).filter(([, e]: [string, any]) => matchesType(type, e.claims));
  // Mehrdeutig (zwei passende Personen gleichen Namens) → lieber nichts.
  if (matching.length !== 1) return null;
  const [qid, entity] = matching[0] as [string, any];
  return { qid, links: socialFromClaims(entity.claims), website: values(entity.claims, "P856")[0] };
}
