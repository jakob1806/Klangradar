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

/** "MarkusTordik" / "Co_Merz" / "Hoederath" → "Markus Tordik" usw. */
function creditFromToken(token: string): string {
  return token.replace(/[_-]+/g, " ").replace(/([a-zäöü])([A-ZÄÖÜ])/g, "$1 $2").replace(/\s+/g, " ").trim();
}

/** Gärtnerplatztheater: Ensembleseiten mit `alt="Portrait NAME"`, Fotograf im
 * Dateinamen ("Berg_cMarkusTordik.jpg"). Geprüft 02.11.2026. */
export function parseGaertnerplatzRoster(html: string, pageUrl: string): ArtistPhoto[] {
  const out = new Map<string, ArtistPhoto>();
  for (const m of html.matchAll(/<img src="(https:\/\/www\.gaertnerplatztheater\.de\/uploads\/[^"?]+?_c([A-ZÄÖÜ][A-Za-zÄÖÜäöüß]+)\.(?:jpe?g|png|webp))(?:\?[^"]*)?"\s+alt="Portrait ([^"]+)"/g)) {
    const name = decode(m[3]);
    if (!name || name.split(" ").length < 2 || out.has(name)) continue;
    out.set(name, { name, imageUrl: m[1], credit: `© ${creditFromToken(m[2])}`, pageUrl });
  }
  return [...out.values()];
}

/** Münchner Philharmoniker: Liste /orchester/musikerinnen-und-musiker. */
export function parseMphilList(html: string): ArtistListEntry[] {
  const seen = new Set<string>();
  return [...html.matchAll(/<a href="(\/ueber-uns\/musikerinnen-und-musiker\/details\/[a-z0-9-]+)">\s*([^<]+?)\s*<\/a>/g)]
    .filter((m) => !seen.has(m[1]) && seen.add(m[1]))
    .map((m) => ({ name: decode(m[2]), detailUrl: `https://www.mphil.de${m[1]}` }));
}

/** MPhil-Detailseite: og:image, Credit im Pfad ("…/credit_Co_Merz/…"). Ohne Credit kein Treffer. */
export function parseMphilDetail(html: string, pageUrl: string, name: string): ArtistPhoto | null {
  const url = html.match(/<meta property="og:image" content="(https:\/\/www\.mphil\.de\/fileadmin\/[^"]+\.(?:jpe?g|png|webp))"/i)?.[1];
  const credit = url?.match(/credit_([A-Za-zÄÖÜäöüß_-]+?)(?:\/|_?\.\w+$)/)?.[1];
  if (!url || !credit) return null;
  return { name, imageUrl: url, credit: `© ${creditFromToken(credit)}`, pageUrl };
}

/** Berliner Philharmoniker: Liste der Musiker:innen. */
export function parseBerlinerPhilList(html: string): ArtistListEntry[] {
  const seen = new Set<string>();
  return [...html.matchAll(/href="(\/ueber-uns\/orchester\/musikerinnen\/([a-z0-9-]+)\/)"/g)]
    .filter((m) => !seen.has(m[1]) && seen.add(m[1]))
    .map((m) => ({ name: titleCase(m[2]), detailUrl: `https://www.berliner-philharmoniker.de${m[1]}` }));
}

/** Berliner-Phil-Detailseite: og:image, Fotograf im Dateinamen ("…_c_Hoederath_32095…"),
 * Name aus dem Seitentitel (mit Umlauten statt Slug). */
export function parseBerlinerPhilDetail(html: string, pageUrl: string, fallbackName: string): ArtistPhoto | null {
  const url = html.match(/<meta property="og:image" content="(https:\/\/www\.berliner-philharmoniker\.de\/fileadmin\/[^"]+\.(?:jpe?g|png|webp))"/i)?.[1];
  const credit = url?.match(/_c_([A-Za-zÄÖÜäöüß-]+(?:_[A-Z][A-Za-zÄÖÜäöüß-]+)?)_/)?.[1];
  if (!url || !credit || /Orchesterfoto/i.test(url)) return null;
  const name = decode(html.match(/<title>([^<|]+)\|/)?.[1] ?? fallbackName);
  return { name, imageUrl: url, credit: `© ${creditFromToken(credit)}`, pageUrl };
}

/** Maestro Arts: Liste /artists mit Links /artists/<slug>. */
export function parseMaestroList(html: string): ArtistListEntry[] {
  const seen = new Set<string>();
  return [...html.matchAll(/href="https:\/\/www\.maestroarts\.com\/artists\/([a-z0-9-]+)"/g)]
    .map((m) => m[1])
    .filter((slug) => slug.includes("-") && !seen.has(slug) && seen.add(slug))
    .map((slug) => ({ name: titleCase(slug), detailUrl: `https://www.maestroarts.com/artists/${slug}` }));
}

/** Maestro-Arts-Detailseite: Galerie-Original (media/…jpg) + erster "© Fotograf". */
export function parseMaestroDetail(html: string, pageUrl: string, name: string): ArtistPhoto | null {
  const url = html.match(/href="(\/\/maestro-arts-production\.s3\.amazonaws\.com\/media\/Artists\/[^"]+\.jpe?g)"/i)?.[1];
  const credit = html.match(/>\s*©\s*([^<\n]{2,60}?)\s*</)?.[1];
  if (!url || !credit) return null;
  return { name, imageUrl: `https:${url}`, credit: `© ${decode(credit)}`, pageUrl };
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
  {
    key: "mphil", label: "Münchner Philharmoniker",
    list: { url: "https://www.mphil.de/orchester/musikerinnen-und-musiker", parse: parseMphilList, detail: parseMphilDetail },
  },
  {
    key: "gaertnerplatz", label: "Staatstheater am Gärtnerplatz", rosterPages: ["solistinnen-und-solisten", "musikalische-leitung"]
      .map((p) => ({ url: `https://www.gaertnerplatztheater.de/de/ensemble/${p}.html`, parse: parseGaertnerplatzRoster })),
  },
  {
    key: "berlinerphil", label: "Berliner Philharmoniker",
    list: { url: "https://www.berliner-philharmoniker.de/ueber-uns/orchester/musikerinnen/", parse: parseBerlinerPhilList, detail: parseBerlinerPhilDetail },
  },
  { key: "maestroarts", label: "Maestro Arts", list: { url: "https://www.maestroarts.com/artists", parse: parseMaestroList, detail: parseMaestroDetail } },
  { key: "askonasholt", label: "Askonas Holt", list: { url: "https://www.askonasholt.com/artists", parse: parseAskonasList, detail: parseAskonasDetail } },
];

/** Vergleichsschlüssel für Namen: ohne Akzente, Satzzeichen, Groß-/Kleinschreibung. */
export function nameKey(name: string): string {
  return name.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/ß/g, "ss").replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
}
