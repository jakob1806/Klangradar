// Erstellt von Claude Code (Konzept Bildabdeckung, 01.11.2026): Porträtfotos
// von Künstler:innen aus offiziellen Quellen – Orchester-Besetzungsseiten und
// Künstleragenturen. Jede Quelle liefert Name, Bild, Fotografen-Credit und
// Quellseite; übernommen wird nur mit Credit (Pressefoto zur redaktionellen
// Nutzung). Geprüft am 01.11.2026: robots.txt erlaubt den Abruf, Seiten sind
// serverseitig gerendert. Bot-Sperren werden nicht umgangen (Bayerisches
// Staatsorchester antwortet mit 403 und fehlt deshalb).

export interface ArtistPhoto {
  name: string;
  imageUrl: string;
  credit: string;
  pageUrl: string;
}

export interface ArtistListEntry {
  name: string;
  detailUrl: string;
}

function decode(text: string): string {
  return text.replace(/&amp;/g, "&").replace(/&copy;/g, "©").replace(/&#039;|&#39;/g, "'").replace(/&quot;/g, '"')
    .replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
}

function titleCase(slugPart: string): string {
  return slugPart.split(/[-_ ]+/).filter(Boolean).map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
}

/** BRSO und Münchner Rundfunkorchester (gleiches WordPress-Theme): Besetzungs-
 * seite mit `title="Name[, Funktion] © Credit"` am Bild. */
export function parseBrRoster(html: string, pageUrl: string): ArtistPhoto[] {
  const out = new Map<string, ArtistPhoto>();
  for (const m of html.matchAll(/<img[^>]*src="([^"]+\/uploads\/sites\/\d+\/[^"]+?\.(?:jpe?g|png|webp))"[^>]*title="([^"]+?)\s*&copy;\s*([^"]+)"/gi)) {
    const name = decode(m[2]).split(",")[0].trim();
    const credit = decode(m[3]).replace(/\\/g, "/");
    if (!name || name.split(" ").length < 2 || out.has(name)) continue;
    out.set(name, { name, imageUrl: m[1].replace(/-\d+x\d+(\.\w+)$/, "$1"), credit: `© ${credit}`, pageUrl });
  }
  return [...out.values()];
}

/** DSO Berlin: Personen-Seiten mit `<img … alt="Name"/><div class="copyright"><span>© Credit`. */
export function parseDsoRoster(html: string, pageUrl: string): ArtistPhoto[] {
  const out = new Map<string, ArtistPhoto>();
  for (const m of html.matchAll(/<img src="(\/media\/image\/[^"]+)"[^>]*alt="([^"]+)"\s*\/?>\s*<div class="copyright"><span>(?:&copy;|©)\s*([^<]+)/g)) {
    const name = decode(m[2]);
    if (!name || out.has(name)) continue;
    out.set(name, { name, imageUrl: `https://www.dso-berlin.de${m[1]}`, credit: `© ${decode(m[3])}`, pageUrl });
  }
  return [...out.values()];
}

/** Intermusica: Liste /artists mit Links /artist/Vorname-Nachname. */
export function parseIntermusicaList(html: string): ArtistListEntry[] {
  const seen = new Set<string>();
  return [...html.matchAll(/href="(https:\/\/www\.intermusica\.com\/artist\/([A-Za-z0-9%-]+))"/g)]
    .filter((m) => !seen.has(m[1]) && seen.add(m[1]))
    .map((m) => ({ name: decodeURIComponent(m[2]).replace(/-/g, " "), detailUrl: m[1] }));
}

/** Intermusica-Detailseite: Download-Link der Galerie mit Credit darunter. */
export function parseIntermusicaDetail(html: string, pageUrl: string, name: string): ArtistPhoto | null {
  const m = html.match(/href="(https:\/\/www\.intermusica\.com\/downloads\/artistgallery\/\d+\/[^"]+\.jpe?g)"[^>]*>Download Photo<\/a>[\s\S]{0,200}?<h4>Credit:\s*([^<]+)<\/h4>/i);
  return m ? { name, imageUrl: m[1], credit: `© ${decode(m[2])}`, pageUrl } : null;
}

const HP_CATEGORIES = new Set(["conductor", "instrumentalist", "singer", "presenter", "composer", "ensemble", "director", "all"]);

/** HarrisonParrott: Liste mit Links /artists/<slug>. */
export function parseHarrisonParrottList(html: string): ArtistListEntry[] {
  const seen = new Set<string>();
  return [...html.matchAll(/href="\/artists\/([a-z0-9-]+)"/g)]
    .map((m) => m[1])
    .filter((slug) => !HP_CATEGORIES.has(slug) && slug.includes("-") && !seen.has(slug) && seen.add(slug))
    .map((slug) => ({ name: titleCase(slug), detailUrl: `https://www.harrisonparrott.com/artists/${slug}` }));
}

/** HarrisonParrott-Detailseite: größte Variante aus data-srcset, Credit "Photo: …". */
export function parseHarrisonParrottDetail(html: string, pageUrl: string, name: string): ArtistPhoto | null {
  const srcset = html.match(/data-srcset="([^"]+)"/)?.[1];
  const credit = html.match(/copyright__text[\s\S]{0,200}?>Photo:\s*([^<]+)</)?.[1];
  if (!srcset || !credit) return null;
  const best = srcset.split(",").map((part) => part.trim().split(/\s+/))
    .map(([url, w]) => ({ url: decode(url), w: Number.parseInt(w ?? "0", 10) }))
    .filter((c) => c.w <= 2600)
    .sort((a, b) => b.w - a.w)[0];
  if (!best) return null;
  return { name, imageUrl: new URL(best.url, "https://www.harrisonparrott.com").toString(), credit: `© ${decode(credit)}`, pageUrl };
}

/** KD Schmid: Liste mit aria-label "Dieser Link führt zu NAME". */
export function parseKdSchmidList(html: string): ArtistListEntry[] {
  const seen = new Set<string>();
  return [...html.matchAll(/aria-label="Dieser Link führt zu ([^"]+)"\s+href="(\/kd-schmid\/artists\/data\/[a-z0-9-]+\.php)"/g)]
    .filter((m) => !seen.has(m[2]) && seen.add(m[2]))
    .map((m) => ({ name: decode(m[1]), detailUrl: `https://www.kdschmid.de${m[2]}` }));
}

/** KD-Schmid-Detailseite: Porträt-Bild, Fotograf steht im Dateinamen ("-c-gisela-schenker-portrait"). */
export function parseKdSchmidDetail(html: string, pageUrl: string, name: string): ArtistPhoto | null {
  const m = html.match(/(\/kd-schmid-wAssets\/img\/artists\/[^"\s]+?-c-([a-z0-9-]+?)-portrait[^"\s]*?@1692w\.webp)/);
  if (!m) return null;
  return { name, imageUrl: `https://www.kdschmid.de${m[1]}`, credit: `© ${titleCase(m[2])}`, pageUrl };
}

/** Askonas Holt: Liste mit Links /artist/<slug>. */
export function parseAskonasList(html: string): ArtistListEntry[] {
  const seen = new Set<string>();
  return [...html.matchAll(/\/artist\/([a-z0-9-]+)/g)]
    .map((m) => m[1])
    .filter((slug) => slug.includes("-") && !seen.has(slug) && seen.add(slug))
    .map((slug) => ({ name: titleCase(slug), detailUrl: `https://www.askonasholt.com/artist/${slug}` }));
}

/** Askonas-Holt-Detailseite: Galerie im eingebetteten JSON. Nur Bilder mit
 * Credit, ohne Bildunterschrift (keine Szenenfotos) und ohne Download-Sperre. */
export function parseAskonasDetail(html: string, pageUrl: string, name: string): ArtistPhoto | null {
  const text = html.replace(/\\"/g, '"');
  for (const m of text.matchAll(/\{"caption":(null|"[^"]*"),"credit":"([^"]+)","image":\{"alt":[^,]*,"height":(\d+),"src":"(https:\/\/cdn\.sanity\.io\/images\/[^"]+)","width":(\d+)\},"shouldDisallowDownload":(true|false|null)\}/g)) {
    if (m[1] !== "null" || m[6] === "true") continue;
    if (Number(m[3]) < Number(m[5])) continue; // Hochformat bevorzugen (Porträt)
    return { name, imageUrl: `${m[4]}?w=1600`, credit: decode(m[2]).replace(/^©?\s*/, "© "), pageUrl };
  }
  return null;
}

export interface ArtistSource {
  key: string;
  label: string;
  /** Listen-/Besetzungsseiten, die direkt Fotos liefern. */
  rosterPages?: { url: string; parse: (html: string, pageUrl: string) => ArtistPhoto[] }[];
  /** Agentur: Liste + Detailseite je Treffer. */
  list?: { url: string; parse: (html: string) => ArtistListEntry[]; detail: (html: string, pageUrl: string, name: string) => ArtistPhoto | null };
}

export const ARTIST_SOURCES: ArtistSource[] = [
  { key: "brso", label: "BR Symphonieorchester", rosterPages: [{ url: "https://www.brso.de/orchester/besetzung/", parse: parseBrRoster }] },
  { key: "mro", label: "Münchner Rundfunkorchester", rosterPages: [{ url: "https://www.rundfunkorchester.de/orchester/besetzung/", parse: parseBrRoster }] },
  {
    key: "dso", label: "DSO Berlin", rosterPages: ["orchestermitglieder", "solisten", "dirigenten", "ehrendirigenten"]
      .map((p) => ({ url: `https://www.dso-berlin.de/de/orchester/personen/${p}/`, parse: parseDsoRoster })),
  },
  { key: "intermusica", label: "Intermusica", list: { url: "https://www.intermusica.com/artists", parse: parseIntermusicaList, detail: parseIntermusicaDetail } },
  { key: "harrisonparrott", label: "HarrisonParrott", list: { url: "https://www.harrisonparrott.com/artists", parse: parseHarrisonParrottList, detail: parseHarrisonParrottDetail } },
  { key: "kdschmid", label: "KD Schmid", list: { url: "https://www.kdschmid.de/kd-schmid/artists/", parse: parseKdSchmidList, detail: parseKdSchmidDetail } },
  { key: "askonasholt", label: "Askonas Holt", list: { url: "https://www.askonasholt.com/artists", parse: parseAskonasList, detail: parseAskonasDetail } },
];

/** Vergleichsschlüssel für Namen: ohne Akzente, Satzzeichen, Groß-/Kleinschreibung. */
export function nameKey(name: string): string {
  return name.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/ß/g, "ss").replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
}
