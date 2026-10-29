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
  // Bei parallelen Läufen drosseln Wikipedia/Wikidata (429/503); ohne
  // Wiederholung fiel das Werk dann auf die unsichere Volltextsuche zurück.
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const res = await fetch(url, { headers: { ...H, Accept: "application/json" } });
      if (res.ok) return await res.json();
      if (res.status !== 429 && res.status < 500) return null;
    } catch {
      // Netzwerkfehler: erneut versuchen
    }
    await new Promise((r) => setTimeout(r, 800 * 2 ** attempt));
  }
  return null;
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
export function candidateTitles(title: string, composer: string | null): { lang: Lang; title: string; trusted?: boolean }[] {
  const surname = (composer ?? "").trim().split(/\s+/).pop() ?? "";
  const out: { lang: Lang; title: string; trusted?: boolean }[] = [];
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
  const quoted = title.match(/»([^«]+)«/)?.[1] ?? title.match(/„([^“”]+)[“”]/)?.[1];
  if (quoted) out.push({ lang: "de", title: quoted });
  // "Ouvertüre aus Die Zauberflöte", "Arien aus der Oper Figaro" → Oper.
  const from = title.match(/\baus (?:der Oper |dem Ballett |dem Oratorium |der Operette )?(?:»|„)?([^»«„“”,(]+?)(?:«|“|”)?(?:[,(]|\s+(?:KV|op\.|BWV|HWV)\b|$)/i)?.[1]?.trim();
  if (from && from.length > 3 && from !== quoted) out.push({ lang: "de", title: from });
  return out;
}

/** HTML-Entities und Anführungszeichen aus Quelltiteln glätten. */
export function normalizeWorkTitle(title: string): string {
  return title.replace(/&quot;/g, "\"").replace(/&amp;/g, "&").replace(/&#39;|&apos;/g, "'").replace(/\s+/g, " ").trim();
}

/** Werkverzeichnisnummer vergleichbar machen: "KV 620" → "kv620",
 * "op. 55" → "op55", "Hob. I:49" / "Hob. 1/49" → "hobi49", "D. 944" → "d944". */
export function catalogKeys(text: string): string[] {
  const out = new Set<string>();
  const re = /\b(KV|K\.|BWV|HWV|WoO|op\.?|Op\.?|D\.?|Hob\.?\s*[IVXL1-9]+[:/.]?|WAB|RV|TrV|Sz\.?|BB)\s*(\d+[a-z]?)(?:\s*(?:Nr\.|No\.|\/)\s*(\d+))?/g;
  for (const m of text.matchAll(re)) {
    let prefix = m[1].toLowerCase().replace(/[.\s]/g, "");
    if (prefix === "k") prefix = "kv";
    if (prefix.startsWith("hob")) prefix = "hob" + prefix.slice(3).replace(/[:/]/g, "").replace(/^1$/, "i");
    out.add(prefix + m[2].toLowerCase() + (m[3] ? "/" + m[3] : ""));
  }
  return [...out];
}

const wikidataCache = new Map<string, Promise<WikidataWork[]>>();
interface WikidataWork { label: string; catalogs: string[]; de: string | null; en: string | null }

/** Alle Werke einer Komponist:in mit Artikeln (de/en) und Katalognummern. */
function wikidataWorks(qid: string): Promise<WikidataWork[]> {
  if (!/^Q\d+$/.test(qid)) return Promise.resolve([]);
  const cached = wikidataCache.get(qid);
  if (cached) return cached;
  const sparql = `SELECT ?w ?label ?cat ?opus ?de ?en WHERE {
    ?w wdt:P86 wd:${qid}.
    OPTIONAL { ?w wdt:P528 ?cat. }
    OPTIONAL { ?w wdt:P10855 ?opus. }
    OPTIONAL { ?de schema:about ?w; schema:isPartOf <https://de.wikipedia.org/>. }
    OPTIONAL { ?en schema:about ?w; schema:isPartOf <https://en.wikipedia.org/>. }
    FILTER(BOUND(?de) || BOUND(?en))
    OPTIONAL { ?w rdfs:label ?label. FILTER(LANG(?label) = "de") }
  } LIMIT 3000`;
  const promise = get(`https://query.wikidata.org/sparql?format=json&query=${encodeURIComponent(sparql)}`).then((data) => {
    const byWork = new Map<string, WikidataWork>();
    for (const b of data?.results?.bindings ?? []) {
      const id = b.w.value;
      const entry = byWork.get(id) ?? { label: "", catalogs: [], de: null, en: null };
      const title = (url?: string) => url ? decodeURIComponent(url.split("/wiki/")[1] ?? "").replace(/_/g, " ") : null;
      entry.de ??= title(b.de?.value);
      entry.en ??= title(b.en?.value);
      if (b.label?.value) entry.label = b.label.value;
      if (b.cat?.value) entry.catalogs.push(...catalogKeys(b.cat.value), b.cat.value.toLowerCase().replace(/[\s.]/g, ""));
      // Opuszahlen stehen in Wikidata separat (P10855: "55", "18 Nr. 1").
      if (b.opus?.value) entry.catalogs.push(...catalogKeys(`op. ${b.opus.value}`));
      byWork.set(id, entry);
    }
    return [...byWork.values()];
  });
  wikidataCache.set(qid, promise);
  return promise;
}

const SYNONYMS: Record<string, string> = {
  symphonie: "sinfonie", symphony: "sinfonie", concerto: "konzert", quartet: "quartett", sonata: "sonate",
  overture: "ouverture", ouvertuere: "ouverture", requiem: "requiem", mass: "messe",
};

function words(value: string): string[] {
  return normalizeName(value).replace(/[^a-z0-9 ]/g, " ").split(/\s+/).map((w) => SYNONYMS[w] ?? w)
    .filter((w) => w.length > 2 && !/^(fur|und|der|die|das|aus|the|and|for|von|mit|nr|op|in|dur|moll|major|minor|orchester|orchestra)$/.test(w));
}

/** Komponist:in ohne hinterlegte Wikidata-ID: Namenssuche, nur Treffer
 * mit Komponisten-Beschreibung. */
async function composerQidByName(name: string): Promise<string | null> {
  const parts = name.trim().split(/\s+/);
  const surname = parts[parts.length - 1] ?? "";
  // Voller Name, sonst nur Nachname ("Peter I. Tschaikowsky" findet
  // Wikidata nicht, "Tschaikowsky" schon) – dann muss der Vorname zum
  // Label passen, damit nicht der falsche Strauss/Bach gewählt wird.
  for (const query of [name, surname]) {
    for (const lang of ["de", "en"]) {
      const data = await get(`https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json&type=item&limit=7&language=${lang}&search=${encodeURIComponent(query)}`);
      const hit = (data?.search ?? []).find((r: any) =>
        /komponist|compos/i.test(r.description ?? "") &&
        (query === name || (normalizeName(r.label ?? "")[0] === normalizeName(parts[0] ?? "")[0] && parts.length > 1)));
      if (hit?.id) return hit.id;
    }
  }
  return null;
}

/** Wikidata-Kandidaten: Katalognummer schlägt Titelähnlichkeit. */
export async function wikidataCandidates(qid: string, title: string, catalog: string | null): Promise<{ lang: Lang; title: string; trusted: boolean }[]> {
  const works = await wikidataWorks(qid).catch(() => []);
  if (!works.length) return [];
  const keys = catalogKeys(`${catalog ?? ""} ${title}`);
  const toCandidates = (w: WikidataWork) => [
    ...(w.de ? [{ lang: "de" as Lang, title: w.de, trusted: true }] : []),
    ...(w.en ? [{ lang: "en" as Lang, title: w.en, trusted: true }] : []),
  ];
  if (keys.length) {
    const hits = works.filter((w) => w.catalogs.some((c) => keys.includes(c)));
    // Eindeutige Nummer (op. 55 kann bei Sammelopus mehrere Werke meinen).
    if (hits.length === 1) return toCandidates(hits[0]);
    if (hits.length > 1) {
      const exact = hits.filter((w) => w.catalogs.some((c) => keys.some((k) => k.includes("/") && c === k)));
      if (exact.length === 1) return toCandidates(exact[0]);
    }
  }
  // Titelähnlichkeit: alle bedeutungstragenden Wörter des Wikidata-Labels
  // bzw. Artikeltitels kommen im Werktitel vor (oder umgekehrt bei kurzen Titeln).
  const titleWords = new Set(words(title));
  const number = title.match(/\b(?:Nr\.|No\.)\s*(\d+)/i)?.[1];
  let bestScore = 0;
  let bestWork: WikidataWork | null = null;
  for (const w of works) {
    for (const name of [w.label, w.de ?? "", w.en ?? ""]) {
      const ws = words(name.replace(/\s*\([^)]*\)\s*$/, ""));
      if (!ws.length) continue;
      const hit = ws.filter((x) => titleWords.has(x)).length;
      const nameNumber = name.match(/^(\d+)\.|\bNo\.\s*(\d+)|\bNr\.\s*(\d+)/);
      const n = nameNumber?.[1] ?? nameNumber?.[2] ?? nameNumber?.[3];
      if (number && n && n !== number) continue;
      if (!number && n && /sinfonie|symphon|konzert|concerto|quartett|quartet|sonate|sonata|trio/i.test(name)) continue;
      const score = hit / ws.length + (number && n === number ? 0.5 : 0);
      if (hit >= 1 && hit === ws.length && score > bestScore) { bestScore = score; bestWork = w; }
    }
  }
  return bestWork ? toCandidates(bestWork) : [];
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

/** Nennt die Einleitung eine andere Nummer desselben Verzeichnisses
 * (KV 550 statt KV 183, D 729 statt D 759), ist es ein anderes Werk. */
export function catalogConflict(extract: string, workTitle: string, catalog: string | null): boolean {
  const ours = catalogKeys(`${catalog ?? ""} ${workTitle}`);
  if (!ours.length) return false;
  const theirs = catalogKeys(extract.slice(0, 500));
  const prefix = (k: string) => k.match(/^[a-z]+/)?.[0] ?? "";
  const base = (k: string) => k.split("/")[0];
  return theirs.some((t) => ours.some((o) => prefix(o) === prefix(t))) &&
    !theirs.some((t) => ours.some((o) => base(o) === base(t)));
}

/** Wikidata-verknüpfte Artikel: Listen/Personen und falsche Tonart raus. */
function isTrustedWorkPage(p: { title: string; extract: string }, workTitle: string): boolean {
  if (/^Liste\b|^List of\b/i.test(p.title)) return false;
  const keys = keyForms(workTitle);
  if (keys && !keys.some((k) => p.extract.toLowerCase().includes(k))) return false;
  return true;
}

async function search(lang: Lang, query: string): Promise<string[]> {
  const data = await get(`https://${lang}.wikipedia.org/w/api.php?action=query&format=json&list=search&srlimit=3&srsearch=${encodeURIComponent(query)}`);
  return (data?.query?.search ?? []).map((r: any) => r.title);
}

export function cleanIntro(text: string, limit = 900): string | null {
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
    if (out.length > 120 && (out + sentence).length > limit) break;
    out += (out ? " " : "") + sentence;
    if (out.length > limit - 140) break;
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

/** Voller Klartext eines Artikels mit "== Abschnitt =="-Markierungen. */
async function fullText(lang: Lang, title: string): Promise<string> {
  const data = await get(`https://${lang}.wikipedia.org/w/api.php?action=query&format=json&prop=extracts&explaintext=1&exsectionformat=wiki&redirects=1&titles=${encodeURIComponent(title)}`);
  return (Object.values(data?.query?.pages ?? {})[0] as any)?.extract ?? "";
}

const CONTEXT_SECTIONS = /^(entstehung|entstehungsgeschichte|hintergrund|geschichte|charakteristik|zur musik|musik|werkbeschreibung|werk|history|background|composition)$/i;

/** Zweiter Absatz der Einführung: erster gehaltvoller Absatz aus
 * Entstehung/Hintergrund/Werkbeschreibung (Nutzerwunsch 25.10.2026:
 * Einführungen ausführlicher). */
function contextParagraphs(text: string): string[] {
  const parts = text.split(/^==+\s*(.+?)\s*==+$/m);
  const out: string[] = [];
  for (let i = 1; i < parts.length && out.length < 2; i += 2) {
    if (!CONTEXT_SECTIONS.test(parts[i].trim())) continue;
    const paragraph = parts[i + 1].split("\n").map((l) => l.trim())
      .find((l) => l.length > 160 && !/^(Besetzung|Instrumentation|Scored)\b/i.test(l));
    const cleaned = paragraph ? cleanIntro(paragraph, 750) : null;
    if (cleaned) out.push(cleaned);
  }
  return out;
}

const LABEL = /^(Satzfolge|Sätze|Satzbezeichnungen|Die Sätze|Movements|Structure)\s*:?\s*$/i;

/** Satzliste aus dem Klartext: Zeilen nach "Satzfolge:" o. ä. bzw. unter
 * einem gleichnamigen Abschnitt, solange sie kurz sind. */
function movementsFromText(text: string): string[] {
  const lines = text.split("\n").map((l) => l.trim());
  for (let i = 0; i < lines.length; i++) {
    const heading = lines[i].match(/^==+\s*(.+?)\s*==+$/)?.[1];
    if (!LABEL.test(heading ?? lines[i]) && !/^Satzfolge\s*:/i.test(lines[i])) continue;
    const items: string[] = [];
    for (let j = i + 1; j < lines.length && items.length < 15; j++) {
      const line = lines[j];
      if (!line) { if (items.length) break; else continue; }
      if (/^==/.test(line) || line.length > 110) break;
      items.push(line.replace(/^(\d+|[IVX]+)[.)]\s*/, ""));
    }
    if (items.length >= 2) return items.map((item, n) => `${n + 1}. ${item}`);
  }
  return [];
}

function best(...lists: string[][]): string[] {
  return lists.filter((l) => l.length >= 2 && l.length <= 16).sort((a, b) => b.length - a.length)[0] ?? [];
}

export async function fetchWorkWikiFacts(title: string, composer: string | null, catalog: string | null, composerQid: string | null = null): Promise<WorkWikiFacts | null> {
  title = normalizeWorkTitle(title);
  const tried = new Set<string>();
  // Wikidata zuerst (Ergänzung 29.10.2026): Werke der Komponist:in mit
  // Werkverzeichnisnummer bzw. Titel → verlinkter Artikel. Trifft Fälle,
  // an denen die Lemma-Raterei scheiterte ("Symphonie Nr. 3 Eroica",
  // "Akademische Festouvertüre", "Pique Dame", Namensvarianten wie
  // Prokofieff/Prokofjew).
  const qid = composerQid ?? (composer ? await composerQidByName(composer) : null);
  const candidates = [...(qid ? await wikidataCandidates(qid, title, catalog) : []), ...candidateTitles(title, composer)];
  let found: Awaited<ReturnType<typeof page>> = null;
  for (const c of candidates) {
    const key = `${c.lang}:${c.title}`;
    if (tried.has(key)) continue;
    tried.add(key);
    const p = await page(c.lang, c.title);
    // Wikidata-Treffer sind über die Komponist:in verknüpft: nur noch
    // Listen-/Personenartikel und falsche Tonart ausschließen.
    if (p && !catalogConflict(p.extract, title, catalog) && (c.trusted ? isTrustedWorkPage(p, title) : isWorkPage(p, composer, title))) { found = p; break; }
  }
  if (!found) {
    const query = [composer, title.replace(/[»«]/g, ""), catalog].filter(Boolean).join(" ");
    for (const lang of ["de", "en"] as const) {
      for (const t of await search(lang, query)) {
        const p = await page(lang, t);
        // Ohne Komponist:in nur bei gleichem Artikeltitel (sonst landete
        // "Minutemade" beim Theater, "Schön ist die Welt" bei einem Film).
        if (!composer && p && !normalizeName(p.title).startsWith(normalizeName(title).slice(0, 14))) continue;
        if (p && !catalogConflict(p.extract, title, catalog) && isWorkPage(p, composer, title)) { found = p; break; }
      }
      if (found) break;
    }
  }
  if (!found) return null;


  // Englischer Treffer: Einführung möglichst aus dem deutschen Artikel.
  let intro = found;
  let enTitle: string | null = found.lang === "en" ? found.title : null;
  if (found.lang === "en") {
    const ll = await get(`https://en.wikipedia.org/w/api.php?action=query&format=json&prop=langlinks&lllang=de&titles=${encodeURIComponent(found.title)}`);
    const deTitle = (Object.values(ll?.query?.pages ?? {})[0] as any)?.langlinks?.[0]?.["*"];
    const dePage = deTitle ? await page("de", deTitle) : null;
    if (dePage) intro = dePage;
  } else {
    const ll = await get(`https://de.wikipedia.org/w/api.php?action=query&format=json&prop=langlinks&lllang=en&titles=${encodeURIComponent(found.title)}`);
    enTitle = (Object.values(ll?.query?.pages ?? {})[0] as any)?.langlinks?.[0]?.["*"] ?? null;
  }
  const deText = intro.lang === "de" ? await fullText("de", intro.title) : "";
  const deMovements = intro.lang === "de" ? best(await movementsFor("de", intro.title), movementsFromText(deText)) : [];
  // Satzliste: deutsch bevorzugt, außer der englische Artikel nennt mehr
  // Sätze (z. B. Beethoven 9: de 2 von 4 in der Liste, en alle 4).
  const enMovements = enTitle ? best(await movementsFor("en", enTitle), movementsFromText(await fullText("en", enTitle))) : [];
  const movements = enMovements.length > deMovements.length ? enMovements : deMovements;
  const lead = cleanIntro(intro.extract);
  const context = intro.lang === "de" ? contextParagraphs(deText) : [];
  const introduction = lead
    ? [lead, ...context.filter((p) => !lead.includes(p.slice(0, 40)))].join("\n\n")
    : null;
  return { introduction, movements, pageUrl: intro.url };
}
