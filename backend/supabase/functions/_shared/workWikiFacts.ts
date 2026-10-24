// Erstellt von Claude Code (25.10.2026): Werkeinführung und Satzfolge ohne
// KI, direkt aus Wikipedia (de, sonst en) – zuverlässig, kostenlos, mit
// Quelle (CC BY-SA). Die KI-Anbieter lieferten wiederholt keine Antwort.
//   Artikel:    zuerst übliche Lemma-Formen ("4. Sinfonie (Bruckner)",
//               "1. Violinkonzert (Schostakowitsch)", "Symphony No. 9
//               (Beethoven)"), dann Volltextsuche; Personen-/Listenartikel
//               werden verworfen.
//   Einführung: Einleitung des Artikels (2–4 Sätze).
//   Sätze:      "1. Satz: …"-Überschriften, Abschnitt "Sätze"/"Satz-
//               bezeichnungen"/"Movements" (Liste oder Tabelle); sonst
//               englische Wikipedia.
const H = { "User-Agent": "Klangradar/1.0 (https://klangradar.com; kontakt@klangradar.com)" };
type Lang = "de" | "en";

async function get(url: string): Promise<any> {
  try {
    const res = await fetch(url, { headers: H });
    return res.ok ? await res.json() : null;
  } catch {
    return null;
  }
}

export interface WorkWikiFacts {
  introduction: string | null;
  movements: string[];
  pageUrl: string | null;
}

const INSTRUMENT_DE: Record<string, string> = {
  violine: "Violinkonzert", klavier: "Klavierkonzert", violoncello: "Cellokonzert", cello: "Cellokonzert",
  horn: "Hornkonzert", harfe: "Harfenkonzert", flöte: "Flötenkonzert", klarinette: "Klarinettenkonzert",
  oboe: "Oboenkonzert", trompete: "Trompetenkonzert", viola: "Bratschenkonzert", orgel: "Orgelkonzert",
};
const INSTRUMENT_EN: Record<string, string> = {
  violine: "Violin Concerto", klavier: "Piano Concerto", violoncello: "Cello Concerto", cello: "Cello Concerto",
  horn: "Horn Concerto", harfe: "Harp Concerto", flöte: "Flute Concerto", klarinette: "Clarinet Concerto",
  oboe: "Oboe Concerto", trompete: "Trumpet Concerto", viola: "Viola Concerto",
};

/** Übliche Lemma-Formen für Gattungswerke mit Nummer. */
export function candidateTitles(title: string, composer: string | null): { lang: Lang; title: string }[] {
  const surname = (composer ?? "").trim().split(/\s+/).pop() ?? "";
  const out: { lang: Lang; title: string }[] = [];
  const number = title.match(/\bNr\.\s*(\d+)/i)?.[1] ?? title.match(/\bNo\.\s*(\d+)/i)?.[1];
  if (surname) {
    if (/\b(Sinfonie|Symphonie|Symphony)\b/i.test(title) && number) {
      out.push({ lang: "de", title: `${number}. Sinfonie (${surname})` }, { lang: "en", title: `Symphony No. ${number} (${surname})` });
    }
    const instrument = title.match(/Konzert für (\w+)/i)?.[1]?.toLowerCase() ?? title.match(/^(\w+)konzert/i)?.[1]?.toLowerCase();
    if (/Konzert/i.test(title) && instrument && INSTRUMENT_DE[instrument]) {
      if (number) out.push({ lang: "de", title: `${number}. ${INSTRUMENT_DE[instrument]} (${surname})` }, { lang: "de", title: `${INSTRUMENT_DE[instrument]} Nr. ${number} (${surname})` });
      out.push({ lang: "de", title: `${INSTRUMENT_DE[instrument]} (${surname})` });
      if (INSTRUMENT_EN[instrument]) out.push({ lang: "en", title: number ? `${INSTRUMENT_EN[instrument]} No. ${number} (${surname})` : `${INSTRUMENT_EN[instrument]} (${surname})` });
    }
  }
  const quoted = title.match(/»([^«]+)«/)?.[1];
  if (quoted) out.push({ lang: "de", title: quoted });
  return out;
}

async function page(lang: Lang, title: string) {
  const data = await get(`https://${lang}.wikipedia.org/w/api.php?action=query&format=json&prop=extracts|info|pageprops&exintro=1&explaintext=1&inprop=url&redirects=1&titles=${encodeURIComponent(title)}`);
  const info: any = data ? Object.values(data.query?.pages ?? {})[0] : null;
  if (!info || info.missing !== undefined || !info.extract || info.pageprops?.disambiguation !== undefined) return null;
  return { lang, title: info.title as string, extract: info.extract as string, url: info.fullurl as string };
}

function normalizeName(value: string): string {
  return value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/(sky|ski|skij|skii)$/, "sk");
}

/** "D-Dur" / "a-Moll" aus dem Werktitel → Schreibweisen in de/en. */
function keyForms(title: string): string[] | null {
  const m = title.match(/\b([A-Ha-h](?:is|es|s)?)-(Dur|Moll)\b/);
  if (!m) return null;
  const de = `${m[1]}-${m[2]}`;
  const base = m[1][0].toUpperCase() === "H" ? "B" : m[1][0].toUpperCase();
  const acc = /is$/.test(m[1]) ? "-sharp" : /(es|s)$/.test(m[1]) && m[1].length > 1 ? "-flat" : "";
  return [de.toLowerCase(), `${base}${acc} ${m[2] === "Dur" ? "major" : "minor"}`.toLowerCase()];
}

function isWorkPage(p: { title: string; extract: string }, composer: string | null, workTitle = ""): boolean {
  if (/^Liste\b|^List of\b/i.test(p.title)) return false;
  const surname = (composer ?? "").split(/\s+/).pop() ?? "";
  // Komponist:in muss in der Einleitung vorkommen (sonst z. B. Roman statt Ouvertüre).
  if (surname && !normalizeName(p.extract.slice(0, 400)).includes(normalizeName(surname).slice(0, 6))) return false;
  // Tonart aus dem Titel muss passen (G-Dur- statt D-Dur-Konzert verwerfen).
  // Eigentitel in »…« muss im Artikel stehen (sonst anderes Werk derselben Person).
  const quoted = workTitle.match(/»([^«]+)«/)?.[1];
  if (quoted && !normalizeName(p.title + " " + p.extract.slice(0, 600)).includes(normalizeName(quoted).slice(0, 12))) return false;
  const keys = keyForms(workTitle);
  if (keys && !keys.some((k) => p.extract.toLowerCase().includes(k))) return false;
  // Personenartikel: Titel = Name der Person bzw. Lebensdaten in der Einleitung.
  if (surname && p.title.includes(surname) && !/[(\d]/.test(p.title)) return false;
  if (/\(\s*\*|\* \d{1,2}\.|\bwar ein\b.*\bKomponist|\bwas an? .*composer\b/i.test(p.extract.slice(0, 300))) return false;
  return true;
}

async function search(lang: Lang, query: string): Promise<string[]> {
  const data = await get(`https://${lang}.wikipedia.org/w/api.php?action=query&format=json&list=search&srlimit=3&srsearch=${encodeURIComponent(query)}`);
  return (data?.query?.search ?? []).map((r: any) => r.title);
}

export function cleanIntro(text: string): string | null {
  const plain = text
    .replace(/\s*\([^()]*[Ѐ-ӿͰ-Ͽ][^()]*\)/g, "")
    .replace(/\s*\[[^\]]*\]/g, "")
    .replace(/[<>]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  // Satzende nur bei ". " + Großbuchstabe und NICHT nach Zahl/Abkürzung.
  const sentences: string[] = [];
  let start = 0;
  for (let i = 0; i < plain.length; i++) {
    if (!".!?".includes(plain[i]) || plain[i + 1] !== " " || !/[A-ZÄÖÜ„"»]/.test(plain[i + 2] ?? "")) continue;
    const before = plain.slice(Math.max(0, i - 6), i);
    if (/(\d|\b(Nr|op|Op|bzw|ca|vgl|St|Dr|z\.B|u\.a|Hob|KV|BWV|WAB|Jh))$/.test(before)) continue;
    sentences.push(plain.slice(start, i + 1).trim());
    start = i + 2;
  }
  if (start < plain.length) sentences.push(plain.slice(start).trim());
  let out = "";
  for (const sentence of sentences) {
    if (out.length > 120 && (out + sentence).length > 560) break;
    out += (out ? " " : "") + sentence;
    if (out.length > 420) break;
  }
  return out.length >= 60 ? out : null;
}

const SECTION = /^(sätze|satzfolge|satzbezeichnungen|aufbau|gliederung|movements|structure)$/i;
const HEADING_DE = /^(?:\d+\.|[IVX]+\.)\s*Satz\s*[:–-]\s*(.+)$/i;

/** Entfernt Markup wiederholt, bis nichts mehr übrig ist (verschachtelte
 * Tags wie "<scr<b>ipt>" würden ein einmaliges Ersetzen überleben). */
function stripTags(value: string): string {
  let previous: string;
  let current = value;
  do {
    previous = current;
    current = current.replace(/<ref[^<>]*\/>/g, "").replace(/<ref[^<>]*>[^<]*<\/ref>/g, "").replace(/<[^<>]*>/g, "");
  } while (current !== previous);
  return current.replace(/[<>]/g, "");
}

function cleanCell(value: string): string {
  return stripTags(value)
    .replace(/^[#*;:|!]+\s*/, "")
    .replace(/style="[^"]*"\s*\|/g, "")
    .replace(/\[\[(?:[^|\]]*\|)?([^\]]+)\]\]/g, "$1")
    .replace(/'''?|''/g, "")
    .replace(/\{\{[^}]*\}\}/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/^Satz\s*:\s*/i, "")
    .replace(/\s+/g, " ")
    .trim();
}

const CYRILLIC = /[\u0400-\u04FF]/;
const EN_HEADING = /^(?:[IVX]+\.?|\d+\.)\s+(.+)$/;
const NUMBERED_LINE = /^[;:#*]*\s*'*\s*([IVX]+|\d+)[.)]\s*'*\s*(.+)$/;

async function movementsFor(lang: Lang, title: string): Promise<string[]> {
  const parsed = await get(`https://${lang}.wikipedia.org/w/api.php?action=parse&format=json&prop=sections&redirects=1&page=${encodeURIComponent(title)}`);
  const sections: { line: string; index: string }[] = parsed?.parse?.sections ?? [];
  const headings = sections.map((s) => cleanCell(s.line).match(HEADING_DE)?.[1]).filter((x): x is string => !!x);
  if (headings.length >= 2) return headings.map((m, i) => `${i + 1}. ${m}`).slice(0, 12);

  if (lang === "en") {
    const enHeadings = sections.map((s) => cleanCell(s.line)).filter((l) => EN_HEADING.test(l));
    if (enHeadings.length >= 2 && enHeadings.length <= 8) return enHeadings;
  }
  const section = sections.find((s) => SECTION.test(cleanCell(s.line)));
  if (!section) return [];
  const wt = await get(`https://${lang}.wikipedia.org/w/api.php?action=parse&format=json&prop=wikitext&redirects=1&section=${section.index}&page=${encodeURIComponent(title)}`);
  const text: string = wt?.parse?.wikitext?.["*"] ?? "";
  // Listen (# / *)
  const listLines = text.split("\n").filter((l) => /^[#*;]/.test(l) || NUMBERED_LINE.test(l));
  let items = listLines.map(cleanCell).filter((l) => l.length > 1 && l.length < 160 && !CYRILLIC.test(l));
  if (items.length >= 2) {
    // Nummerierte Listen (#) ohne eigene Nummer durchzählen.
    const numbered = listLines.every((l) => l.startsWith("#"));
    return items.slice(0, 15).map((item, i) => numbered && !/^([IVX]+|\d+)\./.test(item) ? `${i + 1}. ${item}` : item);
  }
  // Tabellen: pro Zeile die erste Zelle mit Text nach einer römischen Ziffer.
  items = [];
  for (const row of text.split(/\n\|-/).slice(1)) {
    const cells = row.split(/\n\||\|\|/).map(cleanCell).filter(Boolean);
    const numeral = cells.findIndex((c) => /^[IVX]+\.?$/.test(c));
    let name = numeral >= 0 ? cells[numeral + 1] : cells[0];
    // Originaltitel in kyrillischer Schrift → deutsche Übersetzung (nächste Spalte).
    if (name && CYRILLIC.test(name)) name = cells[(numeral >= 0 ? numeral + 1 : 0) + 1] ?? name;
    if (name && name.length < 80 && !/^(Originaltitel|Satz|Nr\.?)$/i.test(name)) items.push(numeral >= 0 ? `${cells[numeral].replace(/\.$/, "")}. ${name}` : name);
  }
  return items.length >= 2 ? items.slice(0, 20) : [];
}

export async function fetchWorkWikiFacts(title: string, composer: string | null, catalog: string | null): Promise<WorkWikiFacts | null> {
  const tried = new Set<string>();
  const candidates = candidateTitles(title, composer);
  let found: Awaited<ReturnType<typeof page>> = null;
  for (const c of candidates) {
    const key = `${c.lang}:${c.title}`;
    if (tried.has(key)) continue;
    tried.add(key);
    const p = await page(c.lang, c.title);
    if (p && isWorkPage(p, composer, title)) { found = p; break; }
  }
  if (!found) {
    const query = [composer, title.replace(/[»«]/g, ""), catalog].filter(Boolean).join(" ");
    for (const lang of ["de", "en"] as const) {
      for (const t of await search(lang, query)) {
        const p = await page(lang, t);
        if (p && isWorkPage(p, composer, title)) { found = p; break; }
      }
      if (found) break;
    }
  }
  if (!found) return null;

  // Englischer Treffer: Einführung möglichst aus dem deutschen Artikel.
  let intro = found;
  if (found.lang === "en") {
    const ll = await get(`https://en.wikipedia.org/w/api.php?action=query&format=json&prop=langlinks&lllang=de&titles=${encodeURIComponent(found.title)}`);
    const deTitle = (Object.values(ll?.query?.pages ?? {})[0] as any)?.langlinks?.[0]?.["*"];
    const dePage = deTitle ? await page("de", deTitle) : null;
    if (dePage) intro = dePage;
  }

  let movements = await movementsFor(found.lang, found.title);
  if (movements.length < 2 && found.lang === "de") {
    // Englischer Artikel desselben Werks über den Sprachlink.
    const ll = await get(`https://de.wikipedia.org/w/api.php?action=query&format=json&prop=langlinks&lllang=en&titles=${encodeURIComponent(found.title)}`);
    const enTitle = (Object.values(ll?.query?.pages ?? {})[0] as any)?.langlinks?.[0]?.["*"];
    if (enTitle) movements = await movementsFor("en", enTitle);
  }
  return { introduction: cleanIntro(intro.extract), movements, pageUrl: intro.url };
}
